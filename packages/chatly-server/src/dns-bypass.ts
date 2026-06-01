import dns from 'dns';

const originalLookup = dns.lookup;

// Mapping of AWS IPv6 prefixes to their respective region names.
// Generated from official AWS IP ranges.
const REGION_PREFIXES: Record<string, string> = {
  '2406:da1a': 'ap-south-1',
  '2406:da1c': 'ap-southeast-1',
  '2406:da12': 'ap-southeast-2',
  '2406:da14': 'ap-northeast-1',
  '2406:da18': 'ap-northeast-2',
  '2600:1f18': 'us-east-1',
  '2600:1f10': 'us-east-1',
  '2600:1f1c': 'us-east-2',
  '2600:1f14': 'us-west-2',
  '2600:1f16': 'us-west-1',
  '2a05:d018': 'eu-west-1',
  '2a05:d01c': 'eu-west-2',
  '2a05:d014': 'eu-central-1',
  '2a05:d016': 'eu-west-3',
  '2600:1f11': 'ca-central-1',
  '2600:1f15': 'sa-east-1',
  '2a05:d01e': 'eu-north-1',
};

const hostMappingCache: Record<string, string> = {};

function getRegionFromIPv6(ipv6: string): string | null {
  const cleanIpv6 = ipv6.toLowerCase().trim();
  for (const [prefix, region] of Object.entries(REGION_PREFIXES)) {
    if (cleanIpv6.startsWith(prefix)) {
      return region;
    }
  }
  return null;
}

// Global lookup interceptor to force IPv4 and reroute IPv6-only Supabase hosts
// @ts-ignore
dns.lookup = function (hostname: any, options: any, callback: any) {
  if (typeof options === 'function') {
    callback = options;
    options = {};
  }

  const hostnameStr = String(hostname || '');

  // Intercept direct connection hosts of Supabase (e.g. db.xxxxx.supabase.co)
  if (hostnameStr.startsWith('db.') && hostnameStr.endsWith('.supabase.co')) {
    if (hostMappingCache[hostnameStr]) {
      const targetHost = hostMappingCache[hostnameStr];
      return originalLookup(targetHost, { ...options, family: 4 }, callback);
    }

    console.log(`[DNS Override] Supabase direct host detected: ${hostnameStr}. Rerouting to connection pooler...`);

    let done = false;
    
    // Set a strict 1.2 second timeout to avoid hanging startup if DNS resolution fails or blocks
    const timer = setTimeout(() => {
      if (!done) {
        done = true;
        // Fallback default: since the user's project is in ap-south-1, use it as default fallback
        const fallbackRegion = process.env.SUPABASE_REGION || 'ap-south-1';
        const targetHost = `aws-0-${fallbackRegion}.pooler.supabase.com`;
        hostMappingCache[hostnameStr] = targetHost;
        console.warn(`[DNS Override] IPv6 resolution timed out. Defaulting to pooler: ${targetHost}`);
        originalLookup(targetHost, { ...options, family: 4 }, callback);
      }
    }, 1200);

    originalLookup(hostnameStr, { family: 6 }, (err, ipv6Address) => {
      if (done) return;
      done = true;
      clearTimeout(timer);

      let region = process.env.SUPABASE_REGION || 'ap-south-1'; // Use detected or project default fallback

      if (!err && ipv6Address) {
        const detectedRegion = getRegionFromIPv6(ipv6Address);
        if (detectedRegion) {
          region = detectedRegion;
          console.log(`[DNS Override] Successfully mapped ${ipv6Address} to region: ${region}`);
        } else {
          console.warn(`[DNS Override] Prefix for IPv6 ${ipv6Address} not found in database. Using region: ${region}`);
        }
      } else {
        console.error(`[DNS Override] Failed to resolve IPv6 for ${hostnameStr}: ${err?.message || 'unknown error'}. Using region: ${region}`);
      }

      const targetHost = `aws-0-${region}.pooler.supabase.com`;
      hostMappingCache[hostnameStr] = targetHost;
      
      console.log(`[DNS Override] Rerouting connection to pooler: ${targetHost}`);
      return originalLookup(targetHost, { ...options, family: 4 }, callback);
    });
    return;
  }

  // Force IPv4 for all other network operations to bypass IPv6 ENETUNREACH on platforms like Render
  const forcedOptions = typeof options === 'number' ? 4 : { ...options, family: 4 };
  return originalLookup(hostname, forcedOptions, callback);
};

try {
  if (typeof dns.setDefaultResultOrder === 'function') {
    dns.setDefaultResultOrder('ipv4first');
  }
} catch (e) {
  // Ignore
}
