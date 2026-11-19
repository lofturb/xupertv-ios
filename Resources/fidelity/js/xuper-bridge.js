/* XuperTV iOS - PalmServiceBridge contra la capa nativa.
 * iOS no tiene Luna. Se emula call()/cancel()/onservicecallback.
 * La peticion va por messageHandlers.xuperService; la respuesta vuelve por
 * window.__xuperServiceResolve(id, json), sin XHR ni timeouts.
 */
(function () {
  "use strict";
  if (window.__xuperIosPalm) return;

  var seq = 0;
  var pending = {};

  function deliver(id, json) {
    var bridge = pending[String(id)];
    if (!bridge) return;
    delete pending[String(id)];
    if (bridge._cancelled) return;
    if (typeof bridge.onservicecallback === "function") {
      try {
        bridge.onservicecallback(String(json));
      } catch (e) {}
    }
  }

  window.__xuperServiceResolve = deliver;

  function PalmServiceBridge() {
    this.onservicecallback = null;
    this._cancelled = false;
    this.m_identifier = "";
  }

  PalmServiceBridge.prototype.call = function (service, params) {
    var id = "xb" + (++seq);
    this.m_identifier = id;
    pending[id] = this;
    var message = { id: id, service: String(service || ""), payload: params || "{}" };
    try {
      window.webkit.messageHandlers.xuperService.postMessage(message);
    } catch (e) {}
  };

  PalmServiceBridge.prototype.cancel = function () {
    this._cancelled = true;
    if (this.m_identifier) delete pending[this.m_identifier];
  };

  window.PalmServiceBridge = PalmServiceBridge;
  window.__xuperIosPalm = true;
})();

