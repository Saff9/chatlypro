import asyncio
import logging
import os
import re
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, Field
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

# ----------------------------------------------------------------------
# System Configuration
# ----------------------------------------------------------------------
# Load environment configurations with sane defaults for local development.
# In production, these are supplied via container env definitions.
MODEL_TYPE = os.getenv("MODEL_TYPE", "original")      # Model variant to load from Detoxify
FALLBACK_THRESHOLD = float(os.getenv("TOXICITY_THRESHOLD", "0.7"))
MAX_TEXT_LENGTH = int(os.getenv("MAX_TEXT_LENGTH", "5000"))
API_KEY = os.getenv("API_KEY", "")                    # If set, incoming requests must supply this key
RATE_LIMIT = os.getenv("RATE_LIMIT", "10/minute")     # slowapi rate limit rule

HOST = os.getenv("HOST", "0.0.0.0")
PORT = int(os.getenv("PORT", "8000"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

# Set up logging format
logging.basicConfig(level=LOG_LEVEL, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("moderation")

# ----------------------------------------------------------------------
# Rate Limiting Configuration
# ----------------------------------------------------------------------
def get_client_ip(request: Request) -> str:
    """
    Retrieves the actual client IP address, respecting proxy setups (like Render/Railway/Nginx)
    by looking at the X-Forwarded-For header before falling back to remote host address.
    """
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        # Fetch the original client IP (first element in X-Forwarded-For chain)
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "127.0.0.1"

# Instantiate rate limiter
limiter = Limiter(key_func=get_client_ip)

# ----------------------------------------------------------------------
# Security Gate (API Key Verification)
# ----------------------------------------------------------------------
api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key: str = Security(api_key_header)):
    """
    Verifies that the request has supplied a valid API Key if one is configured.
    """
    if API_KEY and api_key != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API Key")

# ----------------------------------------------------------------------
# Pydantic Data Validation Models
# ----------------------------------------------------------------------
class TextRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=MAX_TEXT_LENGTH)

# ----------------------------------------------------------------------
# Toxicity Classification Core
# ----------------------------------------------------------------------
class ToxicityDetector:
    def __init__(self):
        self.use_fallback = False
        self.model = None
        self._load_model()

    def _load_model(self):
        """Loads the Detoxify model or falls back to keyword matching on error."""
        try:
            logger.info("Initializing Detoxify model (variant: %s) ...", MODEL_TYPE)
            from detoxify import Detoxify
            self.model = Detoxify(MODEL_TYPE)
            logger.info("Detoxify model loaded successfully.")
        except Exception as e:
            logger.warning("Could not load Detoxify model: %s. Reverting to local keyword fallback.", e)
            self.use_fallback = True
            
            # Blacklisted terms for fallback matching (whole words only)
            self.blacklist = [
                "abuse", "kill", "idiot", "hate", "trash", "stupid",
                "fuck", "bitch", "asshole", "bastard", "crap", "dick",
                "cunt", "slut", "whore", "prick", "rape", "torture",
                "moron", "imbecile", "retard", "scum", "vermin"
            ]

    @staticmethod
    def normalize_leetspeak(text: str) -> str:
        """
        Normalizes leetspeak variants in text to standard characters to prevent evasion
        of keyword and pattern moderation filters.
        """
        mapping = {
            '@': 'a', '4': 'a', '▲': 'a',
            '8': 'b', 'ß': 'b',
            '©': 'c', '¢': 'c', '<': 'c', '(': 'c',
            '3': 'e', '€': 'e',
            '#': 'h',
            '1': 'i', '!': 'i', '|': 'i', '¡': 'i',
            '0': 'o',
            '5': 's', '$': 's', '§': 's',
            '7': 't', '+': 't',
            '\\/\\/': 'w', 'vv': 'w',
            '\\/': 'v',
            '2': 'z'
        }
        normalized = text.lower()
        # Sort keys by length in descending order to avoid short-circuiting nested mappings
        for leet, normal in sorted(mapping.items(), key=lambda x: -len(x[0])):
            normalized = normalized.replace(leet, normal)
        return normalized

    def score(self, text: str) -> float:
        """
        Calculates the toxicity index of a string, returning a score between 0.0 and 1.0.
        """
        if not text.strip():
            return 0.0

        normalized = self.normalize_leetspeak(text)

        if self.use_fallback:
            return self._fallback_score(normalized)
        else:
            return self._model_score(normalized)

    def _fallback_score(self, text: str) -> float:
        """Word-boundary pattern matching fallback scorer to prevent false positives."""
        text_lower = text.lower()
        pattern = r'\b(?:' + '|'.join(re.escape(w) for w in self.blacklist) + r')\b'
        matches = len(re.findall(pattern, text_lower))
        if matches > 0:
            # Recompute toxicity score based on occurrence counts
            return min(0.3 + (matches * 0.25), 0.95)
        return 0.0

    def _model_score(self, text: str) -> float:
        """Runs the neural network classifier on the text input."""
        try:
            results = self.model.predict(text)
            return float(results['toxicity'])
        except Exception as e:
            logger.error("Model prediction failed: %s. Executing keyword matching backup.", e)
            # If the model fails dynamically during runtime (OOM, shape issues, etc.),
            # fallback to keyword matching rather than letting content bypass unmoderated.
            return self._fallback_score(text)

# ----------------------------------------------------------------------
# Lifespan Hook
# ----------------------------------------------------------------------
detector: ToxicityDetector = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global detector
    detector = ToxicityDetector()
    yield
    # Cleanup on shutdown if needed

# ----------------------------------------------------------------------
# Application Setup
# ----------------------------------------------------------------------
app = FastAPI(
    title="Chatly ML Moderation Service",
    version="2.0.0",
    lifespan=lifespan,
)

# SlowAPI Middleware registration
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------------------------------------------------------------
# Thread Pool Executor (Prevents CPU-bound ML calls from blocking Event Loop)
# ----------------------------------------------------------------------
executor = ThreadPoolExecutor(max_workers=2)

async def run_in_executor(func, *args):
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(executor, func, *args)

# ----------------------------------------------------------------------
# Endpoints
# ----------------------------------------------------------------------
@app.post("/analyse")
@limiter.limit(RATE_LIMIT)
async def analyse_toxicity(
    request: Request,
    body: TextRequest,
    api_key: str = Security(verify_api_key),
):
    """Analyzes the toxicity profile of a text string."""
    try:
        score = await run_in_executor(detector.score, body.text)
    except Exception as e:
        logger.exception("Error scoring text payload")
        raise HTTPException(status_code=500, detail="Internal moderation service scoring error")

    is_toxic = score > FALLBACK_THRESHOLD
    return {
        "text": body.text,
        "toxicity_score": score,
        "is_toxic": is_toxic,
        "engine": "fallback" if detector.use_fallback else f"detoxify_{MODEL_TYPE}",
    }

@app.get("/health")
@limiter.exempt
async def health_check():
    """Health status check endpoint."""
    return {
        "status": "healthy",
        "engine": "fallback" if detector.use_fallback else f"detoxify_{MODEL_TYPE}",
    }

# ----------------------------------------------------------------------
# Boot Hook
# ----------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT, log_level=LOG_LEVEL.lower())
