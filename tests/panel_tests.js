// Self-contained panel.html tests; run with build/panel_runner panel.html tests/panel_tests.js
(function () {
  const report = (m) => webkit.messageHandlers.trisplitTest.postMessage(m);
  const LRM = "‎";
  const ODY = LRM + "Odyssey G95C";
  const XSS = "<img src=x onerror=alert(1)>";

  let log = [];
  window.post = (m) => { log.push(JSON.parse(JSON.stringify(m))); };

  const FIXTURE = {
    screens: [
      { name: "LC49G95T", x: 0, y: 0, w: 5120, h: 1440 },
      { name: ODY, x: 5120, y: 0, w: 5120, h: 1440 },
      { name: "Built-in Retina Display", x: 1000, y: 1440, w: 1512, h: 982 },
    ],
    configs: [{
      name: "Trabajo <b>x</b>",
      monitors: {
        "LC49G95T": { cols: 3, rows: 1, slots: ["Code#2", "", LRM + "WhatsApp"] },
        [ODY]: { cols: 2, rows: 1, slots: ["Safari", ""] },
        "Built-in Retina Display": { cols: 1, rows: 1, slots: [""] },
      },
    }],
    active: 1,
    apps: [
      { name: "Code", count: 2, titles: ["main.swift", XSS] },
      { name: "Safari", count: 1, titles: ["x"] },
      { name: LRM + "WhatsApp", count: 1, titles: [""] },
      { name: "<i>Evil</i>", count: 1, titles: ["t"] },
      { name: "Slack", count: 1, titles: [""] },
    ],
    primary: "LC49G95T",
    arrange: {},
    hasDisplayplacer: false,
  };

  function fresh(mut) {
    const s = JSON.parse(JSON.stringify(FIXTURE));
    if (mut) mut(s);
    window.trisplitSetState(s);
    log = [];
    return s;
  }
  const byAction = (a) => log.filter((m) => m.action === a);
  const monBox = (name) => [...document.querySelectorAll(".mon")].find((b) => b.dataset.name === name);
  const tchips = () => [...document.querySelectorAll("#chips .tchip")];
  function slotOf(name, idx) { return monBox(name).querySelectorAll(".slot")[idx - 1]; }
  function drop(slot, payload) {
    slot.ondrop({ preventDefault() {}, dataTransfer: { getData: () => JSON.stringify(payload) } });
  }
  function ptr(el, type, x, y) {
    el.dispatchEvent(new PointerEvent(type, { clientX: x, clientY: y, pointerId: 7, bubbles: true, cancelable: true }));
  }
  function esc(target) {
    (target || document).dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true, cancelable: true }));
  }
  function assert(c, msg) { if (!c) throw new Error(msg); }
  function eq(a, b, msg) { if (a !== b) throw new Error(msg + ": expected " + JSON.stringify(b) + ", got " + JSON.stringify(a)); }

  let pass = 0, fail = 0;
  function test(name, fn) {
    try { fn(); pass++; report("ok - " + name); }
    catch (e) { fail++; report("not ok - " + name + ": " + (e && e.message)); }
    finally { if (document.activeElement && document.activeElement.blur) document.activeElement.blur(); }
  }

  test("ready is posted on DOMContentLoaded via post()", () => {
    log = [];
    document.dispatchEvent(new Event("DOMContentLoaded"));
    eq(byAction("ready").length, 1, "ready count");
  });

  test("post() is the single bridge entry point", () => {
    const src = document.querySelector("script:not([src])").textContent;
    eq((src.match(/postMessage/g) || []).length, 1, "postMessage occurrences in panel script");
  });

  test("partial state does not throw", () => {
    window.trisplitSetState({});
    window.trisplitSetState({ configs: [], active: 1 });
    window.trisplitSetState({ configs: [{ name: "Solo" }], active: 5, screens: [{ name: "X", x: 0, y: 0, w: 10, h: 10 }] });
    eq(document.getElementById("cfg").options[0].textContent, "Solo", "renders config lacking monitors");
    eq(document.getElementById("cfg").value, "0", "out-of-range active clamped");
    fresh();
  });

  test("renders configs", () => {
    fresh((s) => s.configs.push({ name: "Casa", monitors: {} }));
    const opts = [...document.querySelectorAll("#cfg option")].map((o) => o.textContent);
    eq(JSON.stringify(opts), JSON.stringify(["Trabajo <b>x</b>", "Casa"]), "option texts");
    eq(document.querySelectorAll("#cfg b").length, 0, "no <b> element from config name");
  });

  test("renders screens with U+200E names intact", () => {
    fresh();
    const names = [...document.querySelectorAll(".mon")].map((b) => b.dataset.name);
    eq(names.length, 3, "monitor count");
    assert(names.includes(ODY), "LRM-prefixed screen name present");
    eq(monBox(ODY).querySelector(".monhead .nm").textContent, ODY, "screen label");
    eq(monBox(ODY).querySelectorAll(".slot").length, 2, "Odyssey slots");
    eq(slotOf("LC49G95T", 3).querySelector(".chip .nm").textContent, LRM + "WhatsApp", "LRM app chip");
  });

  test("renders apps in tray (one chip per window)", () => {
    fresh();
    eq(tchips().length, 6, "tray chip count");
  });

  test("XSS strings render as text, no elements injected", () => {
    fresh();
    eq(document.querySelectorAll("img:not(.ic)").length, 0, "img elements (icons excluded)");
    eq(document.querySelectorAll("#chips i, #monitors b, #monitors i").length, 0, "injected tags");
    assert(tchips().some((c) => c.textContent.includes("<img src=x")), "title shown literally");
    assert(tchips().some((c) => c.textContent === "<i>Evil</i>"), "app name shown literally");
  });

  test("tray drop into slot posts liveMove + save with correct screen/idx/app", () => {
    fresh();
    drop(slotOf(ODY, 2), { app: "Slack", tray: true });
    const lm = byAction("liveMove"), sv = byAction("save");
    eq(lm.length, 1, "liveMove count");
    eq(JSON.stringify(lm[0]), JSON.stringify({ action: "liveMove", screen: ODY, idx: 2, app: "Slack" }), "liveMove payload");
    eq(sv.length, 1, "save count");
    eq(sv[0].active, 1, "save active");
    eq(sv[0].configs[0].monitors[ODY].slots[1], "Slack", "saved slot");
  });

  test("chip drag between screens swaps and posts liveMove for both", () => {
    fresh();
    drop(slotOf(ODY, 1), { app: "Code#2", screen: "LC49G95T", idx: 1 });
    const lm = byAction("liveMove");
    eq(lm.length, 2, "liveMove count");
    eq(JSON.stringify(lm[0]), JSON.stringify({ action: "liveMove", screen: ODY, idx: 1, app: "Code#2" }), "first move");
    eq(JSON.stringify(lm[1]), JSON.stringify({ action: "liveMove", screen: "LC49G95T", idx: 1, app: "Safari" }), "second move");
    eq(byAction("save").length, 1, "save count");
  });

  test("placed flag is keyed by full spec (Code vs Code#2, App == App#1)", () => {
    fresh((s) => { s.configs[0].monitors[ODY].slots = ["Safari#1", ""]; });
    const flag = (label) => tchips().find((c) => c.textContent.startsWith(label)).classList.contains("placed");
    eq(flag("Code · ventana 1"), false, "Code v1 placed");
    eq(flag("Code · ventana 2"), true, "Code v2 placed");
    eq(flag("Safari"), true, "Safari placed via Safari#1");
    eq(flag("Slack"), false, "Slack placed");
    eq(flag(LRM + "WhatsApp"), true, "LRM WhatsApp placed");
  });

  test("Esc posts close", () => {
    fresh();
    esc();
    eq(JSON.stringify(log), JSON.stringify([{ action: "close" }]), "messages");
  });

  test("Esc while editing new-config name cancels edit, no close", () => {
    fresh();
    document.getElementById("new").click();
    const inp = document.getElementById("newname");
    inp.value = "draft";
    assert(document.activeElement === inp, "input focused");
    esc(inp);
    eq(byAction("close").length, 0, "close count");
    eq(inp.style.display, "none", "input hidden");
    esc();
    eq(byAction("close").length, 1, "close after edit cancelled");
  });

  test("delete disabled with one config, enabled with two", () => {
    fresh();
    const del = document.getElementById("del");
    eq(del.disabled, true, "disabled with 1");
    assert(del.title.length > 0, "tooltip present");
    del.click();
    eq(log.length, 0, "no message when disabled");
    fresh((s) => s.configs.push({ name: "Casa", monitors: {} }));
    eq(del.disabled, false, "enabled with 2");
    del.click(); del.click();
    eq(byAction("save").length, 1, "delete saves");
    eq(byAction("save")[0].configs.length, 1, "one config left");
    eq(del.disabled, true, "disabled again");
  });

  test("arrange click without move posts nothing (no NaN)", () => {
    fresh();
    const box = monBox(ODY);
    ptr(box, "pointerdown", 400, 200);
    ptr(box, "pointermove", 400, 200);
    ptr(monBox(ODY), "pointerup", 400, 200);
    eq(byAction("arrange").length, 0, "arrange posts");
    assert(!JSON.stringify(log).includes("null"), "no NaN-as-null in any message");
    eq(document.querySelectorAll(".ghost, .guide").length, 0, "drag artifacts left");
  });

  test("arrange drag posts finite offsets once; listeners removed after pointerup", () => {
    fresh();
    const box = monBox(ODY);
    ptr(box, "pointerdown", 400, 200);
    ptr(box, "pointermove", 460, 230);
    ptr(box, "pointerup", 460, 230);
    const a = byAction("arrange");
    eq(a.length, 1, "arrange count");
    const o = a[0].offsets[ODY];
    assert(o && Number.isFinite(o.dx) && Number.isFinite(o.dy), "finite offsets: " + JSON.stringify(a[0].offsets));
    ptr(box, "pointermove", 600, 300);
    ptr(box, "pointerup", 600, 300);
    eq(byAction("arrange").length, 1, "stale listener posted again");
    eq(document.querySelectorAll(".ghost, .guide, .mon.lifted").length, 0, "drag artifacts left");
  });

  test("pointercancel ends arrange drag without posting", () => {
    fresh();
    const box = monBox(ODY);
    ptr(box, "pointerdown", 400, 200);
    ptr(box, "pointermove", 480, 260);
    ptr(box, "pointercancel", 480, 260);
    eq(byAction("arrange").length, 0, "arrange posts");
    eq(document.querySelectorAll(".ghost, .guide, .mon.lifted").length, 0, "drag artifacts left");
    ptr(box, "pointerup", 480, 260);
    eq(byAction("arrange").length, 0, "listener survived cancel");
  });

  test("primary monitor header uses the move cursor like the others", () => {
    fresh();
    const cur = (n) => getComputedStyle(monBox(n).querySelector(".monhead")).cursor;
    eq(cur("LC49G95T"), cur(ODY), "primary vs secondary cursor");
  });

  test("repeated setState does not duplicate handlers", () => {
    fresh(); fresh(); fresh();
    document.getElementById("apply").click();
    eq(JSON.stringify(log), JSON.stringify([{ action: "apply" }]), "apply click");
    log = [];
    esc();
    eq(byAction("close").length, 1, "Esc close count");
    log = [];
    drop(slotOf(ODY, 2), { app: "Slack", tray: true });
    eq(byAction("liveMove").length, 1, "liveMove count");
    eq(byAction("save").length, 1, "save count");
  });

  test("H: window index labelled 'ventana N' in chip and tray", () => {
    fresh();
    eq(slotOf("LC49G95T", 1).querySelector(".chip .nm").textContent, "Code", "chip name");
    eq(slotOf("LC49G95T", 1).querySelector(".chip .win").textContent, "ventana 2", "chip window index");
    assert(tchips().some((c) => c.textContent.startsWith("Code · ventana 1")), "tray label");
    assert(!document.body.textContent.includes(" · v2"), "no legacy ' · v2'");
  });

  test("B: empty tray shows no-apps message", () => {
    fresh((s) => { s.apps = []; });
    eq(document.querySelector("#chips .empty").textContent, "No hay apps con ventanas visibles", "no-apps message");
    fresh();
    eq(document.querySelectorAll("#chips .empty").length, 0, "no message with apps");
  });

  test("B2: no filter input in the tray", () => {
    fresh();
    eq(document.getElementById("filter"), null, "no #filter");
  });

  test("I: occupied chip shows app icon from trisplit-icon scheme (window suffix stripped)", () => {
    fresh();
    const ic = slotOf("LC49G95T", 1).querySelector(".chip img.ic");
    assert(ic, "icon img");
    eq(ic.getAttribute("src"), "trisplit-icon://app/Code", "icon src for Code#2");
  });

  test("I2: icon load error swaps in the initial fallback", () => {
    fresh();
    const chip = slotOf("LC49G95T", 1).querySelector(".chip");
    chip.querySelector("img.ic").onerror();
    eq(chip.querySelector("img.ic"), null, "img removed");
    eq(chip.querySelector(".ic.fallback").textContent, "C", "fallback initial");
  });

  test("I3: ✕ is an svg cross and still clears the slot", () => {
    fresh();
    const x = slotOf("LC49G95T", 1).querySelector(".chip .x");
    assert(x.querySelector("svg"), "svg inside ✕");
    eq(x.getAttribute("aria-label"), "Quitar", "aria-label");
    x.onclick({ stopPropagation() {} });
    assert(!slotOf("LC49G95T", 1).querySelector(".chip"), "slot cleared");
  });

  test("C: banner reports disconnected monitors of the config", () => {
    fresh();
    eq(getComputedStyle(document.getElementById("banner")).display, "none", "banner hidden when all connected");
    fresh((s) => { s.configs[0].monitors["Dell U2720"] = { cols: 2, rows: 1, slots: ["Mail", ""] }; });
    eq(document.getElementById("banner").style.display, "flex", "banner shown");
    eq(document.getElementById("monLine").textContent.trim(),
      "1 monitor(es) de esta configuración no están conectados — sus huecos se conservan", "banner text");
  });

  test("A: axTrusted false shows banner with Abrir Ajustes posting openAXSettings", () => {
    fresh();
    eq(document.getElementById("axLine").style.display, "none", "hidden when axTrusted absent");
    fresh((s) => { s.axTrusted = false; });
    eq(document.getElementById("banner").style.display, "flex", "banner shown");
    const line = document.getElementById("axLine");
    eq(line.style.display, "flex", "ax line shown");
    assert(line.textContent.includes("Trisplit necesita permiso de Accesibilidad para mover ventanas"), "ax text");
    const btn = document.getElementById("openAX");
    eq(btn.textContent, "Abrir Ajustes…", "button label");
    btn.click();
    eq(JSON.stringify(log), JSON.stringify([{ action: "openAXSettings" }]), "openAX message");
  });

  test("D/E/F: keyboard a11y, stepper limits, cmd-enter", () => {
    fresh();
    const chip = slotOf("LC49G95T", 1).querySelector(".chip");
    eq(chip.tabIndex, 0, "chip focusable");
    const x = chip.querySelector(".x");
    eq(x.tagName, "BUTTON", "x is a button"); eq(x.title, "Quitar", "x title");
    chip.dispatchEvent(new KeyboardEvent("keydown", { key: "Delete", bubbles: true, cancelable: true }));
    eq(byAction("save")[0].configs[0].monitors["LC49G95T"].slots[0], "", "Delete removes chip");
    fresh();
    tchips().find((c) => c.textContent === "Slack").dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }));
    eq(JSON.stringify(byAction("liveMove")[0]), JSON.stringify({ action: "liveMove", screen: "LC49G95T", idx: 2, app: "Slack" }), "Enter places in first free");
    fresh();
    const btns = monBox("Built-in Retina Display").querySelectorAll(".stepper button");
    eq(btns[0].disabled, true, "col minus disabled at 1"); eq(btns[2].disabled, true, "row minus disabled at 1");
    assert(btns[1].title && btns[1].getAttribute("aria-label"), "stepper title/aria");
    fresh((s) => { s.configs[0].monitors[ODY] = { cols: 6, rows: 4, slots: Array(24).fill("") }; });
    const b2 = monBox(ODY).querySelectorAll(".stepper button");
    eq(b2[1].disabled, true, "col plus disabled at 6"); eq(b2[3].disabled, true, "row plus disabled at 4");
    fresh();
    document.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", metaKey: true, bubbles: true, cancelable: true }));
    eq(JSON.stringify(log), JSON.stringify([{ action: "applyAndClose" }]), "cmd-enter");
    assert(document.getElementById("apply").title.includes("⌘↩"), "apply title mentions ⌘↩");
  });

  test("absent chips: closed apps greyed, open ones not", () => {
    fresh((s) => {
      s.configs[0].monitors["Built-in Retina Display"].slots = ["Mail"];
      s.apps.push({ name: "Visual Studio Code", count: 1, titles: [""] });
      s.apps = s.apps.filter((a) => a.name !== "Code");
      s.configs[0].monitors[ODY].slots = ["Safari", "Code"];
    });
    const chipAt = (n, i) => slotOf(n, i).querySelector(".chip");
    const absent = chipAt("Built-in Retina Display", 1);
    assert(absent.classList.contains("absent"), "Mail (closed) marked absent");
    eq(absent.title, "No está abierta", "absent tooltip");
    const safari = chipAt(ODY, 1);
    assert(!safari.classList.contains("absent"), "Safari (open) not absent");
    eq(safari.title, "", "present chip has no absent tooltip");
    assert(!chipAt("LC49G95T", 3).classList.contains("absent"), "U+200E WhatsApp matches");
    assert(!chipAt(ODY, 2).classList.contains("absent"), "alias Code -> Visual Studio Code");
    fresh();
    assert(!chipAt("LC49G95T", 1).classList.contains("absent"), "Code#2 suffix matches Code");
    fresh((s) => { s.apps = s.apps.filter((a) => a.name !== "Code"); });
    assert(chipAt("LC49G95T", 1).classList.contains("absent"), "Code#2 absent when Code closed");
  });

  function fakeDT() {
    const d = {};
    return { effectAllowed: "", setData: (k, v) => { d[k] = v; }, getData: (k) => d[k] || "" };
  }

  test("state push during chip drag is deferred; dragend applies it", () => {
    fresh();
    const chip = slotOf(ODY, 1).querySelector(".chip");
    chip.ondragstart({ dataTransfer: fakeDT() });
    assert(!document.body.classList.contains("is-dragging"), "is-dragging deferred past dragstart");
    const s2 = JSON.parse(JSON.stringify(FIXTURE));
    s2.configs[0].monitors[ODY].slots = ["Safari", "Slack"];
    window.trisplitSetState(s2);
    assert(slotOf(ODY, 1).querySelector(".chip") === chip, "dragged chip node survives the push");
    assert(chip.isConnected, "dragged chip still in DOM");
    assert(!slotOf(ODY, 2).querySelector(".chip"), "pending state not rendered yet");
    chip.ondragend();
    const c2 = slotOf(ODY, 2).querySelector(".chip");
    assert(c2 && c2.textContent.includes("Slack"), "pending state applied on dragend");
    assert(slotOf(ODY, 1).querySelector(".chip") !== chip, "re-rendered after dragend");
  });

  test("drop during chip drag keeps the swap on top of the pending push", () => {
    fresh();
    const chip = slotOf("LC49G95T", 1).querySelector(".chip");
    const dt = fakeDT();
    chip.ondragstart({ dataTransfer: dt });
    const s2 = JSON.parse(JSON.stringify(FIXTURE));
    s2.apps.push({ name: "Mail", count: 1, titles: [""] });
    s2.configs[0].monitors["Built-in Retina Display"].slots = ["Mail"];
    window.trisplitSetState(s2);
    slotOf(ODY, 1).ondrop({ preventDefault() {}, dataTransfer: dt });
    chip.ondragend();
    const saves = byAction("save");
    eq(saves.length, 1, "save count");
    const mons = saves[0].configs[0].monitors;
    eq(mons[ODY].slots[0], "Code#2", "swap target");
    eq(mons["LC49G95T"].slots[0], "Safari", "swap source");
    eq(mons["Built-in Retina Display"].slots[0], "Mail", "pending state folded in");
    assert(slotOf("Built-in Retina Display", 1).querySelector(".chip").textContent.includes("Mail"), "rendered");
  });

  const CHROME2 = [{ name: "Google Chrome", count: 2, titles: ["a", "b"] }];
  const chromeChips = () => tchips().filter((c) => c.textContent.startsWith("Google Chrome · ventana"));

  test("stray drag: document dragend without chip dragend unparks later pushes", () => {
    fresh();
    tchips()[0].ondragstart({ dataTransfer: fakeDT() });
    document.dispatchEvent(new Event("dragend", { bubbles: true }));
    fresh((s) => { s.apps = CHROME2; });
    eq(chromeChips().length, 2, "chrome tray chips");
    assert(!document.body.classList.contains("is-dragging"), "is-dragging cleared");
  });

  test("stray drag: pointerdown on document unparks later pushes", () => {
    fresh();
    tchips()[0].ondragstart({ dataTransfer: fakeDT() });
    ptr(document.body, "pointerdown", 1, 1);
    fresh((s) => { s.apps = CHROME2; });
    eq(chromeChips().length, 2, "chrome tray chips");
  });

  test("stale drag watchdog: push >15 s after dragstart is applied", () => {
    fresh();
    const realNow = Date.now;
    try {
      const t0 = realNow();
      Date.now = () => t0;
      tchips()[0].ondragstart({ dataTransfer: fakeDT() });
      Date.now = () => t0 + 1000;
      fresh((s) => { s.apps = CHROME2; });
      eq(chromeChips().length, 0, "push parked during live drag");
      Date.now = () => t0 + 16000;
      fresh((s) => { s.apps = CHROME2; });
      eq(chromeChips().length, 2, "stale drag: push applied");
    } finally { Date.now = realNow; }
    fresh();
  });

  const LC = "LC49G95T";
  const lcSaved = () => { const sv = byAction("save"); return sv[sv.length - 1].configs[0].monitors[LC].slots; };

  test("span: '<' renders as one wide slot", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code#2", "<", ""]; });
    const slots = monBox(LC).querySelectorAll(".slot");
    eq(slots.length, 2, "marker cell not rendered");
    eq(slots[0].style.gridColumn, "span 2", "owner spans 2");
    assert(slots[0].querySelector(".sp.grow"), "grow shown: right cell is empty");
    assert(slots[0].querySelector(".sp.shrink"), "shrink shown");
  });

  test("span: ▶ grows into the empty right slot", () => {
    fresh();
    const g = slotOf(LC, 1).querySelector(".sp.grow");
    assert(g, "grow shown next to empty slot");
    g.onclick({ stopPropagation() {} });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code#2", "<", LRM + "WhatsApp"]), "saved");
    const lm = byAction("liveMove");
    eq(JSON.stringify(lm[lm.length - 1]), JSON.stringify({ action: "liveMove", screen: LC, idx: 1, app: "Code#2" }), "liveMove");
    assert(!slotOf(LC, 2).querySelector(".sp.grow"), "no grow at row end (WhatsApp is now .slot 2)");
  });

  test("span: − shrinks back", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code#2", "<", ""]; });
    slotOf(LC, 1).querySelector(".sp.shrink").onclick({ stopPropagation() {} });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code#2", "", ""]), "saved");
  });

  test("span: ✕ clears the owner and its continuation", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code#2", "<", ""]; });
    slotOf(LC, 1).querySelector(".x").onclick({ stopPropagation() {} });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["", "", ""]), "saved");
  });

  test("span: orphan markers are normalized away", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["<", "", "<"]; });
    eq(monBox(LC).querySelectorAll(".slot").length, 3, "three plain cells");
    assert(!monBox(LC).querySelector(".slot .chip"), "no chips for orphans");
  });

  test("span: tray drop on a wide slot drops its continuation", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code#2", "<", ""]; });
    drop(monBox(LC).querySelectorAll(".slot")[0], { app: "Slack", tray: true });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Slack", "", ""]), "saved");
  });

  const USER = ["", "Code", "Google Chrome"];
  const key = (el, k) => el.dispatchEvent(new KeyboardEvent("keydown", { key: k, shiftKey: true, bubbles: true, cancelable: true }));
  const lastMove = () => { const lm = byAction("liveMove"); return JSON.stringify(lm[lm.length - 1]); };

  test("span: user layout shows ◀ on Code, nothing else", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = USER.slice(); });
    const code = slotOf(LC, 2);
    const b = code.querySelector(".sp.left");
    assert(b, "Code chip has a grow-left button");
    eq(b.textContent, "◀", "glyph");
    assert(b.title.includes("izquierda") && b.title.includes("⇧←"), "title mentions shortcut");
    eq(b.draggable, false, "button not draggable");
    assert(!code.querySelector(".sp.grow") && !code.querySelector(".sp.shrink"), "no grow-right/shrink");
    assert(!slotOf(LC, 3).querySelector(".sp"), "Chrome: left occupied, row end on right");
  });

  test("span: ◀ grows into the empty left slot", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = USER.slice(); });
    slotOf(LC, 2).querySelector(".sp.left").onclick({ stopPropagation() {} });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code", "<", "Google Chrome"]), "saved");
    eq(lastMove(), JSON.stringify({ action: "liveMove", screen: LC, idx: 1, app: "Code" }), "liveMove new owner");
    const owner = slotOf(LC, 1);
    eq(owner.style.gridColumn, "span 2", "owner spans 2");
    assert(!owner.querySelector(".sp.left"), "no grow-left in first column");
    const sh = owner.querySelector(".sp.shrink");
    assert(sh, "shrink shown");
    eq(sh.textContent, "−", "shrink glyph");
  });

  test("span: shrink after grow-left frees the right column", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code", "<", "Google Chrome"]; });
    slotOf(LC, 1).querySelector(".sp.shrink").onclick({ stopPropagation() {} });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code", "", "Google Chrome"]), "saved");
    eq(lastMove(), JSON.stringify({ action: "liveMove", screen: LC, idx: 1, app: "Code" }), "liveMove");
  });

  test("span: ◀ keeps the existing continuation chain", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["", "Code", "<"]; });
    slotOf(LC, 2).querySelector(".sp.left").onclick({ stopPropagation() {} });
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code", "<", "<"]), "saved");
  });

  test("span: ◀ not offered in first column or when left is occupied", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code", "", "Google Chrome"]; });
    assert(!slotOf(LC, 1).querySelector(".sp.left"), "first column");
    fresh((s) => { s.configs[0].monitors[LC].slots = ["Code", "Slack", "Google Chrome"]; });
    assert(!slotOf(LC, 2).querySelector(".sp.left"), "left occupied");
    assert(!slotOf(LC, 3).querySelector(".sp.left"), "left occupied (row end)");
  });

  test("span: keyboard ⇧← / ⇧↓ / ⇧→", () => {
    fresh((s) => { s.configs[0].monitors[LC].slots = USER.slice(); });
    const saves = () => byAction("save").length;
    let n = saves();
    key(slotOf(LC, 3).querySelector(".chip"), "ArrowLeft");
    eq(saves(), n, "⇧← on Chrome is a no-op (left occupied)");
    key(slotOf(LC, 2).querySelector(".chip"), "ArrowLeft");
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code", "<", "Google Chrome"]), "⇧← grows left");
    key(slotOf(LC, 1).querySelector(".chip"), "ArrowDown");
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code", "", "Google Chrome"]), "⇧↓ shrinks");
    key(slotOf(LC, 1).querySelector(".chip"), "ArrowRight");
    eq(JSON.stringify(lcSaved()), JSON.stringify(["Code", "<", "Google Chrome"]), "⇧→ grows right");
    n = saves();
    key(slotOf(LC, 1).querySelector(".chip"), "ArrowRight");
    eq(saves(), n, "⇧→ at row end is a no-op");
  });

  report("panel: " + pass + " passed, " + fail + " failed");
})();
