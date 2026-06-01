import dns from 'dns';

// Override dns.lookup globally to force IPv4 (family: 4) resolution for all sockets.
// This bypasses the ENETUNREACH IPv6 issues on host environments like Render.
const originalLookup = dns.lookup;
// @ts-ignore
dns.lookup = function (hostname: any, options: any, callback: any) {
  if (typeof options === 'function') {
    callback = options;
    options = { family: 4 };
  } else if (typeof options === 'number') {
    options = 4;
  } else if (options && typeof options === 'object') {
    options.family = 4;
  } else {
    options = { family: 4 };
  }
  return originalLookup(hostname, options, callback);
};

// Also set default result order to prefer IPv4
try {
  if (typeof dns.setDefaultResultOrder === 'function') {
    dns.setDefaultResultOrder('ipv4first');
  }
} catch (e) {
  // Ignore if not supported in the running Node environment
}
