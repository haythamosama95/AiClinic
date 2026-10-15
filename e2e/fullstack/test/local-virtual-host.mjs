import { Agent } from "undici";

// Route an HTTP request to a local Wrangler port while keeping the requested
// virtual host in the URL authority (and therefore in the Worker Request URL).
const dispatchers = new Map();

function dispatcherFor(hostname) {
  let dispatcher = dispatchers.get(hostname);
  if (!dispatcher) {
    dispatcher = new Agent({
      connect: {
        lookup(_hostname, _options, callback) {
          callback(null, "127.0.0.1", 4);
        },
      },
    });
    dispatchers.set(hostname, dispatcher);
  }
  return dispatcher;
}

export function localVirtualHostUrl(target, authorityHost) {
  const url = new URL(target);
  url.hostname = authorityHost;
  return url;
}

export function fetchLocalVirtualHost(target, authorityHost, init = {}) {
  const url = localVirtualHostUrl(target, authorityHost);
  return fetch(url, { ...init, dispatcher: dispatcherFor(authorityHost) });
}

export async function closeLocalVirtualHostDispatchers() {
  await Promise.all([...dispatchers.values()].map((dispatcher) => dispatcher.close()));
  dispatchers.clear();
}
