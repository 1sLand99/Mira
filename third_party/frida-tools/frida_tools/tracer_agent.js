(function(){function r(e,n,t){function o(i,f){if(!n[i]){if(!e[i]){var c="function"==typeof require&&require;if(!f&&c)return c(i,!0);if(u)return u(i,!0);var a=new Error("Cannot find module '"+i+"'");throw a.code="MODULE_NOT_FOUND",a}var p=n[i]={exports:{}};e[i][0].call(p.exports,function(r){var n=e[i][1][r];return o(n||r)},p,p.exports,r,e,n,t)}return n[i].exports}for(var u="function"==typeof require&&require,i=0;i<t.length;i++)o(t[i]);return o}return r})()({1:[function(require,module,exports){
(function (global){(function (){
"use strict";

class e {
  constructor() {
    this.handlers = new Map, this.stackDepth = new Map, this.traceState = {}, this.nextId = 1, 
    this.started = Date.now(), this.pendingEvents = [], this.flushTimer = null, this.cachedModuleResolver = null, 
    this.cachedObjcResolver = null, this.flush = () => {
      if (null !== this.flushTimer && (clearTimeout(this.flushTimer), this.flushTimer = null), 
      0 === this.pendingEvents.length) return;
      const e = this.pendingEvents;
      this.pendingEvents = [], send({
        type: "events:add",
        events: e
      });
    };
  }
  init(e, t, s, n) {
    const o = global;
    o.stage = e, o.parameters = t, o.state = this.traceState;
    for (const e of s) try {
      (0, eval)(e.source);
    } catch (t) {
      throw new Error(`Unable to load ${e.filename}: ${t.stack}`);
    }
    this.start(n).catch((e => {
      send({
        type: "agent:error",
        message: e.message
      });
    }));
  }
  dispose() {
    this.flush();
  }
  update(e, t, s) {
    const n = this.handlers.get(e);
    if (void 0 === n) throw new Error("Invalid target ID");
    const o = this.parseHandler(t, s);
    n[0] = o[0], n[1] = o[1];
  }
  async start(e) {
    const t = {
      native: new Map,
      java: []
    }, s = [];
    for (const [n, o, a] of e) switch (o) {
     case "module":
      "include" === n ? this.includeModule(a, t) : this.excludeModule(a, t);
      break;

     case "function":
      "include" === n ? this.includeFunction(a, t) : this.excludeFunction(a, t);
      break;

     case "relative-function":
      "include" === n && this.includeRelativeFunction(a, t);
      break;

     case "imports":
      "include" === n && this.includeImports(a, t);
      break;

     case "objc-method":
      "include" === n ? this.includeObjCMethod(a, t) : this.excludeObjCMethod(a, t);
      break;

     case "java-method":
      s.push([ n, a ]);
      break;

     case "debug-symbol":
      "include" === n && this.includeDebugSymbol(a, t);
    }
    let n, o = !0;
    if (s.length > 0) {
      if (!Java.available) throw new Error("Java runtime is not available");
      n = new Promise(((e, n) => {
        Java.perform((() => {
          o = !1;
          for (const [e, n] of s) "include" === e ? this.includeJavaMethod(n, t) : this.excludeJavaMethod(n, t);
          this.traceJavaTargets(t.java).then(e).catch(n);
        }));
      }));
    } else n = Promise.resolve();
    await this.traceNativeTargets(t.native), o || await n, send({
      type: "agent:initialized"
    }), n.then((() => {
      send({
        type: "agent:started",
        count: this.handlers.size
      });
    }));
  }
  async traceNativeTargets(e) {
    const t = new Map, s = new Map;
    for (const [n, [o, a, r]] of e.entries()) {
      const e = "objc" === o ? s : t;
      let i = e.get(a);
      void 0 === i && (i = [], e.set(a, i)), i.push([ r, ptr(n) ]);
    }
    return await Promise.all([ this.traceNativeEntries("c", t), this.traceNativeEntries("objc", s) ]);
  }
  async traceNativeEntries(e, s) {
    if (0 === s.size) return;
    const n = this.nextId, o = [], a = {
      type: "handlers:get",
      flavor: e,
      baseId: n,
      scopes: o
    };
    for (const [e, t] of s.entries()) o.push({
      name: e,
      members: t.map((e => e[0]))
    }), this.nextId += t.length;
    const {scripts: r} = await t(a);
    let i = 0;
    for (const e of s.values()) for (const [t, s] of e) {
      const e = n + i, o = "string" == typeof t ? t : t[1], a = this.parseHandler(o, r[i]);
      this.handlers.set(e, a);
      try {
        Interceptor.attach(s, this.makeNativeListenerCallbacks(e, a));
      } catch (e) {
        send({
          type: "agent:warning",
          message: `Skipping "${t}": ${e.message}`
        });
      }
      i++;
    }
  }
  async traceJavaTargets(e) {
    const s = this.nextId, n = [], o = {
      type: "handlers:get",
      flavor: "java",
      baseId: s,
      scopes: n
    };
    for (const t of e) for (const [e, {methods: s}] of t.classes.entries()) {
      const t = e.split("."), o = t[t.length - 1], a = Array.from(s.keys()).map((e => [ e, `${o}.${e}` ]));
      n.push({
        name: e,
        members: a
      }), this.nextId += a.length;
    }
    const {scripts: a} = await t(o);
    return new Promise((t => {
      Java.perform((() => {
        let n = 0;
        for (const t of e) {
          const e = Java.ClassFactory.get(t.loader);
          for (const [o, {methods: r}] of t.classes.entries()) {
            const t = e.use(o);
            for (const [e, o] of r.entries()) {
              const r = s + n, i = this.parseHandler(o, a[n]);
              this.handlers.set(r, i);
              const c = t[e];
              for (const e of c.overloads) e.implementation = this.makeJavaMethodWrapper(r, e, i);
              n++;
            }
          }
        }
        t();
      }));
    }));
  }
  makeNativeListenerCallbacks(e, t) {
    const s = this;
    return {
      onEnter(n) {
        s.invokeNativeHandler(e, t[0], this, n, ">");
      },
      onLeave(n) {
        s.invokeNativeHandler(e, t[1], this, n, "<");
      }
    };
  }
  makeJavaMethodWrapper(e, t, s) {
    const n = this;
    return function(...o) {
      return n.handleJavaInvocation(e, t, s, this, o);
    };
  }
  handleJavaInvocation(e, t, s, n, o) {
    this.invokeJavaHandler(e, s[0], n, o, ">");
    const a = t.apply(n, o), r = this.invokeJavaHandler(e, s[1], n, a, "<");
    return void 0 !== r ? r : a;
  }
  invokeNativeHandler(e, t, s, n, o) {
    const a = Date.now() - this.started, r = s.threadId, i = this.updateDepth(r, o);
    t.call(s, ((...t) => {
      this.emit([ e, a, r, i, t.join(" ") ]);
    }), n, this.traceState);
  }
  invokeJavaHandler(e, t, s, n, o) {
    const a = Date.now() - this.started, r = Process.getCurrentThreadId(), i = this.updateDepth(r, o), c = (...t) => {
      this.emit([ e, a, r, i, t.join(" ") ]);
    };
    try {
      return t.call(s, c, n, this.traceState);
    } catch (e) {
      if (void 0 !== e.$h) throw e;
      Script.nextTick((() => {
        throw e;
      }));
    }
  }
  updateDepth(e, t) {
    const s = this.stackDepth;
    let n = s.get(e) ?? 0;
    return ">" === t ? s.set(e, n + 1) : (n--, 0 !== n ? s.set(e, n) : s.delete(e)), 
    n;
  }
  parseHandler(e, t) {
    try {
      const e = (0, eval)("(" + t + ")");
      return [ e.onEnter ?? u, e.onLeave ?? u ];
    } catch (t) {
      return send({
        type: "agent:warning",
        message: `Invalid handler for "${e}": ${t.message}`
      }), [ u, u ];
    }
  }
  includeModule(e, t) {
    const {native: s} = t;
    for (const t of this.getModuleResolver().enumerateMatches(`exports:${e}!*`)) s.set(t.address.toString(), n(t));
  }
  excludeModule(e, t) {
    const {native: s} = t;
    for (const t of this.getModuleResolver().enumerateMatches(`exports:${e}!*`)) s.delete(t.address.toString());
  }
  includeFunction(e, t) {
    const s = r(e), {native: o} = t;
    for (const e of this.getModuleResolver().enumerateMatches(`exports:${s.module}!${s.function}`)) o.set(e.address.toString(), n(e));
  }
  excludeFunction(e, t) {
    const s = r(e), {native: n} = t;
    for (const e of this.getModuleResolver().enumerateMatches(`exports:${s.module}!${s.function}`)) n.delete(e.address.toString());
  }
  includeRelativeFunction(e, t) {
    const s = i(e), n = Module.getBaseAddress(s.module).add(s.offset);
    t.native.set(n.toString(), [ "c", s.module, `sub_${s.offset.toString(16)}` ]);
  }
  includeImports(e, t) {
    let s;
    if (null === e) {
      const e = Process.enumerateModules()[0].path;
      s = this.getModuleResolver().enumerateMatches(`imports:${e}!*`);
    } else s = this.getModuleResolver().enumerateMatches(`imports:${e}!*`);
    const {native: o} = t;
    for (const e of s) o.set(e.address.toString(), n(e));
  }
  includeObjCMethod(e, t) {
    const {native: s} = t;
    for (const t of this.getObjcResolver().enumerateMatches(e)) s.set(t.address.toString(), o(t));
  }
  excludeObjCMethod(e, t) {
    const {native: s} = t;
    for (const t of this.getObjcResolver().enumerateMatches(e)) s.delete(t.address.toString());
  }
  includeJavaMethod(e, t) {
    const s = t.java, n = Java.enumerateMethods(e);
    for (const e of n) {
      const {loader: t} = e, n = h(s, (e => {
        const {loader: s} = e;
        return null !== s && null !== t ? s.equals(t) : s === t;
      }));
      if (void 0 === n) {
        s.push(c(e));
        continue;
      }
      const {classes: o} = n;
      for (const t of e.classes) {
        const {name: e} = t, s = o.get(e);
        if (void 0 === s) {
          o.set(e, l(t));
          continue;
        }
        const {methods: n} = s;
        for (const e of t.methods) {
          const t = d(e), s = n.get(t);
          void 0 === s ? n.set(t, e) : n.set(t, e.length > s.length ? e : s);
        }
      }
    }
  }
  excludeJavaMethod(e, t) {
    const s = t.java, n = Java.enumerateMethods(e);
    for (const e of n) {
      const {loader: t} = e, n = h(s, (e => {
        const {loader: s} = e;
        return null !== s && null !== t ? s.equals(t) : s === t;
      }));
      if (void 0 === n) continue;
      const {classes: o} = n;
      for (const t of e.classes) {
        const {name: e} = t, s = o.get(e);
        if (void 0 === s) continue;
        const {methods: n} = s;
        for (const e of t.methods) {
          const t = d(e);
          n.delete(t);
        }
      }
    }
  }
  includeDebugSymbol(e, t) {
    const {native: s} = t;
    for (const t of DebugSymbol.findFunctionsMatching(e)) s.set(t.toString(), a(t));
  }
  emit(e) {
    this.pendingEvents.push(e), null === this.flushTimer && (this.flushTimer = setTimeout(this.flush, 50));
  }
  getModuleResolver() {
    let e = this.cachedModuleResolver;
    return null === e && (e = new ApiResolver("module"), this.cachedModuleResolver = e), 
    e;
  }
  getObjcResolver() {
    let e = this.cachedObjcResolver;
    if (null === e) {
      try {
        e = new ApiResolver("objc");
      } catch (e) {
        throw new Error("Objective-C runtime is not available");
      }
      this.cachedObjcResolver = e;
    }
    return e;
  }
}

async function t(e) {
  const t = [], {type: n, flavor: o, baseId: a} = e, r = e.scopes.slice().map((({name: e, members: t}) => ({
    name: e,
    members: t.slice()
  })));
  let i = a;
  do {
    const e = [], a = {
      type: n,
      flavor: o,
      baseId: i,
      scopes: e
    };
    let c = 0;
    for (const {name: t, members: s} of r) {
      const n = [];
      e.push({
        name: t,
        members: n
      });
      let o = !1;
      for (const e of s) if (n.push(e), c++, 1e3 === c) {
        o = !0;
        break;
      }
      if (s.splice(0, n.length), o) break;
    }
    for (;0 !== r.length && 0 === r[0].members.length; ) r.splice(0, 1);
    send(a);
    const l = await s(`reply:${i}`);
    t.push(...l.scripts), i += c;
  } while (0 !== r.length);
  return {
    scripts: t
  };
}

function s(e) {
  return new Promise((t => {
    recv(e, (e => {
      t(e);
    }));
  }));
}

function n(e) {
  const [t, s] = e.name.split("!", 2);
  return [ "c", t, s ];
}

function o(e) {
  const {name: t} = e, [s, n] = t.substr(2, t.length - 3).split(" ", 2);
  return [ "objc", s, [ n, t ] ];
}

function a(e) {
  const t = DebugSymbol.fromAddress(e);
  return [ "c", t.moduleName ?? "", t.name ];
}

function r(e) {
  const t = e.split("!", 2);
  let s, n;
  return 1 === t.length ? (s = "*", n = t[0]) : (s = "" === t[0] ? "*" : t[0], n = "" === t[1] ? "*" : t[1]), 
  {
    module: s,
    function: n
  };
}

function i(e) {
  const t = e.split("!", 2);
  return {
    module: t[0],
    offset: parseInt(t[1], 16)
  };
}

function c(e) {
  return {
    loader: e.loader,
    classes: new Map(e.classes.map((e => [ e.name, l(e) ])))
  };
}

function l(e) {
  return {
    methods: new Map(e.methods.map((e => [ d(e), e ])))
  };
}

function d(e) {
  const t = e.indexOf("(");
  return -1 === t ? e : e.substr(0, t);
}

function h(e, t) {
  for (const s of e) if (t(s)) return s;
}

function u() {}

const f = new e;

rpc.exports = {
  init: f.init.bind(f),
  dispose: f.dispose.bind(f),
  update: f.update.bind(f)
};

}).call(this)}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})

},{}]},{},[1])
//# sourceMappingURL=data:application/json;charset=utf-8;base64,eyJ2ZXJzaW9uIjozLCJzb3VyY2VzIjpbIm5vZGVfbW9kdWxlcy9icm93c2VyLXBhY2svX3ByZWx1ZGUuanMiLCJhZ2VudC50cyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiQUFBQTs7OztBQ0FBLE1BQU07RUFBTjtJQUNZLEtBQUEsV0FBVyxJQUFJLEtBQ2YsS0FBQSxhQUFhLElBQUksS0FDakIsS0FBQSxhQUF5QixJQUN6QixLQUFBLFNBQVM7SUFDVCxLQUFBLFVBQVUsS0FBSyxPQUVmLEtBQUEsZ0JBQThCLElBQzlCLEtBQUEsYUFBa0IsTUFFbEIsS0FBQSx1QkFBMkM7SUFDM0MsS0FBQSxxQkFBeUMsTUFnZ0J6QyxLQUFBLFFBQVE7TUFNWixJQUx3QixTQUFwQixLQUFLLGVBQ0wsYUFBYSxLQUFLLGFBQ2xCLEtBQUssYUFBYTtNQUdZLE1BQTlCLEtBQUssY0FBYyxRQUNuQjtNQUdKLE1BQU0sSUFBUyxLQUFLO01BQ3BCLEtBQUssZ0JBQWdCLElBRXJCLEtBQUs7UUFDRCxNQUFNO1FBQ047O0FBQ0Y7QUF3QlY7RUF0aUJJLEtBQUssR0FBYyxHQUE2QixHQUEyQjtJQUN2RSxNQUFNLElBQUk7SUFDVixFQUFFLFFBQVEsR0FDVixFQUFFLGFBQWEsR0FDZixFQUFFLFFBQVEsS0FBSztJQUVmLEtBQUssTUFBTSxLQUFVLEdBQ2pCO09BQ0ksR0FBSSxNQUFNLEVBQU87TUFDbkIsT0FBTztNQUNMLE1BQU0sSUFBSSxNQUFNLGtCQUFrQixFQUFPLGFBQWEsRUFBRTs7SUFJaEUsS0FBSyxNQUFNLEdBQU0sT0FBTTtNQUNuQixLQUFLO1FBQ0QsTUFBTTtRQUNOLFNBQVMsRUFBRTs7QUFDYjtBQUVWO0VBRUE7SUFDSSxLQUFLO0FBQ1Q7RUFFQSxPQUFPLEdBQW1CLEdBQWM7SUFDcEMsTUFBTSxJQUFVLEtBQUssU0FBUyxJQUFJO0lBQ2xDLFNBQWdCLE1BQVosR0FDQSxNQUFNLElBQUksTUFBTTtJQUdwQixNQUFNLElBQWEsS0FBSyxhQUFhLEdBQU07SUFDM0MsRUFBUSxLQUFLLEVBQVcsSUFDeEIsRUFBUSxL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QUFTLEVBQW1CO0VBQ3hCLE9BQU8sSUFBSSxTQUFRO0lBQ2YsS0FBSyxJQUFPO01BQ1IsRUFBUTtBQUFTO0FBQ25CO0FBRVY7O0FBRUEsU0FBUyxFQUE4QjtFQUNuQyxPQUFPLEdBQVksS0FBZ0IsRUFBRSxLQUFLLE1BQU0sS0FBSztFQUNyRCxPQUFPLEVBQUMsS0FBSyxHQUFZO0FBQzdCOztBQUVBLFNBQVMsRUFBMEI7RUFDL0IsT0FBTSxNQUFFLEtBQVMsSUFDVixHQUFXLEtBQWMsRUFBSyxPQUFPLEdBQUcsRUFBSyxTQUFTLEdBQUcsTUFBTSxLQUFLO0VBQzNFLE9BQU8sRUFBQyxRQUFRLEdBQVcsRUFBQyxHQUFZO0FBQzVDOztBQUVBLFNBQVMsRUFBNkI7RUFDbEMsTUFBTSxJQUFTLFlBQVksWUFBWTtFQUN2QyxPQUFPLEVBQUMsS0FBSyxFQUFPLGNBQWMsSUFBSSxFQUFPO0FBQ2pEOztBQUVBLFNBQVMsRUFBMkI7RUFDaEMsTUFBTSxJQUFTLEVBQVEsTUFBTSxLQUFLO0VBRWxDLElBQUksR0FBRztFQVNQLE9BUnNCLE1BQWxCLEVBQU8sVUFDUCxJQUFJLEtBQ0osSUFBSSxFQUFPLE9BRVgsSUFBbUIsT0FBZCxFQUFPLEtBQWEsTUFBTSxFQUFPLElBQ3RDLElBQW1CLE9BQWQsRUFBTyxLQUFhLE1BQU0sRUFBTztFQUduQztJQUNILFFBQVE7SUFDUixVQUFVOztBQUVsQjs7QUFFQSxTQUFTLEVBQTZCO0VBQ2xDLE1BQU0sSUFBUyxFQUFRLE1BQU0sS0FBSztFQUVsQyxPQUFPO0lBQ0gsUUFBUSxFQUFPO0lBQ2YsUUFBUSxTQUFTLEVBQU8sSUFBSTs7QUFFcEM7O0FBRUEsU0FBUyxFQUE4QjtFQUNuQyxPQUFPO0lBQ0gsUUFBUSxFQUFNO0lBQ2QsU0FBUyxJQUFJLElBQ1QsRUFBTSxRQUFRLEtBQUksS0FBUyxFQUFDLEVBQU0sTUFBTSxFQUE4Qjs7QUFFbEY7O0FBRUEsU0FBUyxFQUE4QjtFQUNuQyxPQUFPO0lBQ0gsU0FBUyxJQUFJLElBQ1QsRUFBTSxRQUFRLEtBQUksS0FBWSxFQUFDLEVBQWlDLElBQVc7O0FBRXZGOztBQUVBLFNBQVMsRUFBaUM7RUFDdEMsTUFBTSxJQUFpQixFQUFTLFFBQVE7RUFDeEMsUUFBNEIsTUFBcEIsSUFBeUIsSUFBVyxFQUFTLE9BQU8sR0FBRztBQUNuRTs7QUFFQSxTQUFTLEVBQVEsR0FBWTtFQUN6QixLQUFLLE1BQU0sS0FBVyxHQUNsQixJQUFJLEVBQVUsSUFDVixPQUFPO0FBR25COztBQUVBLFNBQVMsS0FDVDs7QUE2RkEsTUFBTSxJQUFRLElBQUk7O0FBRWxCLElBQUksVUFBVTtFQUNWLE1BQU0sRUFBTSxLQUFLLEtBQUs7RUFDdEIsU0FBUyxFQUFNLFFBQVEsS0FBSztFQUM1QixRQUFRLEVBQU0sT0FBTyxLQUFLIiwiZmlsZSI6ImdlbmVyYXRlZC5qcyIsInNvdXJjZVJvb3QiOiIifQ==
