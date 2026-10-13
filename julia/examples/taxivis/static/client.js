/* One writer per page. Coalesce waiting edits by query, preserving the latest. */
class RequestQueue {
  constructor(send) { this.send = send; this.pending = new Map(); this.running = false; }
  push(key, url, body) {
    return new Promise((resolve, reject) => {
      const old = this.pending.get(key);
      this.pending.set(key, {url, body: key === 'view' ? {...old?.body, ...body} : body, listeners: [...(old?.listeners || []), {resolve, reject}]});
      this.drain();
    });
  }
  async drain() {
    if (this.running) return;
    this.running = true;
    try {
      while (this.pending.size) {
        const [key, task] = this.pending.entries().next().value;
        this.pending.delete(key);
        try {
          const result = await this.send(task.url, task.body);
          task.listeners.forEach(p => p.resolve(result));
        } catch (error) { task.listeners.forEach(p => p.reject(error)); }
      }
    } finally { this.running = false; }
  }
}
async function requestJSON(url, body) {
  const response = await fetch(url, body === undefined ? {signal: AbortSignal.timeout(15000)} : {
    signal: AbortSignal.timeout(15000),
    method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || `Request failed (${response.status})`);
  return result;
}
if (typeof module !== 'undefined') module.exports = {RequestQueue, requestJSON};
