import os
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Chatly ML Moderation Service", version="1.0.0")

class TextRequest(BaseModel):
    text: str

# Toxicity Detector Class with fallback
class ToxicityDetector:
    def __init__(self):
        self.use_fallback = False
        try:
            print("Loading Detoxify BERT model...")
            from detoxify import Detoxify
            self.model = Detoxify('original')
            print("Detoxify model loaded successfully.")
        except Exception as e:
            print(f"Warning: Could not load Detoxify model: {e}")
            print("Falling back to lightweight keyword-based toxicity detection.")
            self.use_fallback = True
            
            # Simple list of offensive word roots for mockup fallback
            self.blacklist = ["abuse", "kill", "idiot", "hate", "trash", "stupid", "fuck", "bitch", "asshole", "bastard", "crap", "dick", "cunt", "slut", "whore", "prick", "rape", "torture"]

    def normalize_leetspeak(self, text: str) -> str:
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
            '\\/\\/': 'w',
            '\\/': 'v',
            '2': 'z'
        }
        normalized = text.lower()
        # Replace longer patterns first
        for leet, normal in sorted(mapping.items(), key=lambda x: -len(x[0])):
            normalized = normalized.replace(leet, normal)
        return normalized

    def score(self, text: str) -> float:
        if not text.strip():
            return 0.0
            
        normalized = self.normalize_leetspeak(text)
        
        if self.use_fallback:
            # Fallback simple search scoring
            text_lower = normalized.lower()
            matches = sum(1 for word in self.blacklist if word in text_lower)
            if matches > 0:
                # Return score proportional to matches capped at 0.95
                return min(0.3 + (matches * 0.25), 0.95)
            return 0.05
        else:
            # Model prediction
            try:
                results = self.model.predict(normalized)
                return float(results['toxicity'])
            except Exception as e:
                print(f"Error during model prediction: {e}")
                return 0.0

detector = ToxicityDetector()

@app.post("/analyse")
async def analyse_toxicity(request: TextRequest):
    try:
        score = detector.score(request.text)
        is_toxic = score > 0.7
        return {
            "text": request.text,
            "toxicity_score": score,
            "is_toxic": is_toxic,
            "engine": "fallback" if detector.use_fallback else "detoxify_bert"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "engine": "fallback" if detector.use_fallback else "detoxify_bert"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
