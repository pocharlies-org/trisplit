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
    eq(document.querySelector("#profiles .tab").textContent, "Solo", "renders config lacking monitors");
    eq(document.querySelector("#profiles .tab").getAttribute("aria-selected"), "true", "out-of-range active clamped");
    fresh();
  });

  test("renders configs", () => {
    fresh((s) => s.configs.push({ name: "Casa", monitors: {} }));
    const opts = [...document.querySelectorAll("#profiles .tab")].map((o) => o.textContent);
    eq(JSON.stringify(opts), JSON.stringify(["Trabajo <b>x</b>", "Casa"]), "tab texts");
    eq(document.querySelectorAll("#profiles b").length, 0, "no <b> element from config name");
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

  test("save precedes liveMove for swap, span grow and tray drop", () => {
    const firstIdx = (a) => log.findIndex((m) => m.action === a);
    fresh();
    drop(slotOf(ODY, 1), { app: "Code#2", screen: "LC49G95T", idx: 1 });
    assert(firstIdx("save") >= 0 && firstIdx("save") < firstIdx("liveMove"), "swap: save before liveMove");
    fresh();
    slotOf("LC49G95T", 1).querySelector(".sp.grow").onclick({ stopPropagation() {} });
    assert(firstIdx("save") >= 0 && firstIdx("save") < firstIdx("liveMove"), "span: save before liveMove");
    fresh();
    drop(slotOf(ODY, 2), { app: "Slack", tray: true });
    assert(firstIdx("save") >= 0 && firstIdx("save") < firstIdx("liveMove"), "tray drop: save before liveMove");
  });

  test("minimized window chip is dimmed in the tray", () => {
    fresh((s) => { s.apps[0].minimized = [false, true]; });
    const c = tchips().filter((x) => x.textContent.startsWith("Code · ventana"));
    eq(c[0].classList.contains("min"), false, "window 1 normal");
    eq(c[1].classList.contains("min"), true, "window 2 dimmed");
    eq(c[1].title, "Minimizada", "title");
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

  // ---- profiles ----
  const ptabs = () => [...document.querySelectorAll("#profiles .tab")];
  const pnames = () => ptabs().map((t) => t.textContent);
  const withProfiles = (names) => fresh((s) => { names.forEach((n) => s.configs.push({ name: n, monitors: JSON.parse(JSON.stringify(s.configs[0].monitors)) })); });
  const tkey = (el, key, o) => el.dispatchEvent(new KeyboardEvent("keydown", Object.assign({ key, bubbles: true, cancelable: true }, o || {})));
  const menuItem = (label) => [...document.querySelectorAll("#profmenu button")].find((b) => b.textContent.startsWith(label));
  const openMenu = () => document.getElementById("profMenuBtn").click();
  const dt = () => { const d = {}; return { types: [], setData(k, v) { d[k] = v; this.types.push(k); }, getData(k) { return d[k] || ""; } }; };
  const lastSave = () => byAction("save")[byAction("save").length - 1];

  test("P: one tab per profile, active one selected, roving tabindex", () => {
    withProfiles(["Casa", "Viaje"]);
    eq(ptabs().length, 3, "tabs");
    eq(ptabs().map((t) => t.getAttribute("aria-selected")).join(), "true,false,false", "selected");
    eq(ptabs().map((t) => t.tabIndex).join(), "0,-1,-1", "tabindex");
    eq(document.getElementById("profiles").getAttribute("role"), "tablist", "role");
    eq(ptabs()[0].getAttribute("role"), "tab", "tab role");
    eq(document.querySelector("#cfg"), null, "old select gone");
  });

  test("P: click switches profile and saves", () => {
    withProfiles(["Casa"]);
    ptabs()[1].click();
    eq(ptabs()[1].getAttribute("aria-selected"), "true", "now selected");
    eq(lastSave().active, 2, "saved active");
    const n = byAction("save").length;
    ptabs()[1].click();
    eq(byAction("save").length, n, "clicking the active tab saves nothing");
  });

  test("P: arrows move focus, Enter/Space activate", () => {
    withProfiles(["Casa", "Viaje"]);
    ptabs()[0].focus();
    tkey(ptabs()[0], "ArrowRight");
    assert(document.activeElement === ptabs()[1], "focus moved right");
    tkey(ptabs()[1], "Enter");
    eq(ptabs()[1].getAttribute("aria-selected"), "true", "Enter activates");
    tkey(ptabs()[2], " ");
    eq(ptabs()[2].getAttribute("aria-selected"), "true", "Space activates");
    assert(document.activeElement === ptabs()[2], "focus stays on active tab");
  });

  test("P: rename via dblclick commits on Enter (trimmed)", () => {
    withProfiles(["Casa"]);
    ptabs()[0].ondblclick();
    const inp = document.querySelector("#profiles input.tab-edit");
    assert(inp && document.activeElement === inp, "input focused");
    inp.value = "  Oficina  ";
    tkey(inp, "Enter");
    eq(document.querySelector("#profiles input"), null, "input gone");
    eq(pnames().join("|"), "Oficina|Casa", "renamed");
    eq(lastSave().configs[0].name, "Oficina", "saved");
  });

  test("P: rename via F2 and Enter on the active tab; blur commits", () => {
    withProfiles(["Casa"]);
    tkey(ptabs()[0], "F2");
    let inp = document.querySelector("#profiles input.tab-edit");
    assert(inp, "F2 opens input");
    inp.value = "Uno"; inp.onblur();
    eq(pnames()[0], "Uno", "blur commits");
    tkey(ptabs()[0], "Enter");
    assert(document.querySelector("#profiles input.tab-edit"), "Enter on active opens input");
  });

  test("P: rename Esc cancels, nothing saved, no window close", () => {
    withProfiles(["Casa"]);
    ptabs()[0].ondblclick();
    const inp = document.querySelector("#profiles input.tab-edit");
    inp.value = "Otro";
    esc(inp);
    eq(document.querySelector("#profiles input"), null, "input gone");
    eq(pnames()[0], "Trabajo <b>x</b>", "unchanged");
    eq(byAction("save").length, 0, "no save");
    eq(byAction("close").length, 0, "no close");
  });

  test("P: rename rejects empty and duplicate names (red outline, tooltip, no save)", () => {
    withProfiles(["Casa"]);
    ptabs()[1].ondblclick();
    const inp = document.querySelector("#profiles input.tab-edit");
    inp.value = "   "; tkey(inp, "Enter");
    assert(inp.classList.contains("invalid") && inp.title.length > 0, "empty flagged");
    assert(document.querySelector("#profiles input.tab-edit"), "still editing");
    inp.value = "trabajo <B>X</b>"; tkey(inp, "Enter");
    assert(inp.classList.contains("invalid"), "duplicate (case-insensitive) flagged");
    eq(byAction("save").length, 0, "nothing saved");
    inp.value = "Casa"; tkey(inp, "Enter");
    eq(byAction("save").length, 0, "same own name = no-op, no save");
    eq(document.querySelector("#profiles input"), null, "editing ended");
  });

  test("P: duplicate details", () => {
    fresh((s) => { s.configs[0].name = "Dev"; s.configs.push({ name: "Dev copia", monitors: {} }); });
    openMenu(); menuItem("Duplicar").click();
    const sv = lastSave();
    eq(sv.configs.map((c) => c.name).join("|"), "Dev|Dev copia 2|Dev copia", "named copia 2 and inserted right after");
    eq(sv.active, 2, "copy is active");
    const inp = document.querySelector("#profiles input.tab-edit");
    assert(inp && inp.value === "Dev copia 2", "rename mode on the copy");
    eq(JSON.stringify(sv.configs[1].monitors), JSON.stringify(sv.configs[0].monitors), "same monitors incl. spans");
    inp.onblur();
    // edit the copy's slots: the original must not change
    const before = JSON.stringify(lastSave().configs[0].monitors);
    slotOf("LC49G95T", 3).querySelector(".x").onclick({ stopPropagation() {} });
    const after = lastSave();
    eq(JSON.stringify(after.configs[0].monitors), before, "original untouched");
    assert(JSON.stringify(after.configs[1].monitors) !== before, "copy changed");
  });

  test("P: reorder by drag and drop keeps the active profile active", () => {
    withProfiles(["Casa", "Viaje"]);
    ptabs()[1].click(); // active = Casa (index 1)
    const d = dt();
    ptabs()[1].ondragstart({ dataTransfer: d });
    ptabs()[0].ondrop({ preventDefault() {}, stopPropagation() {}, dataTransfer: d });
    eq(lastSave().configs.map((c) => c.name).join("|"), "Casa|Trabajo <b>x</b>|Viaje", "order");
    eq(lastSave().active, 1, "active follows Casa");
    eq(ptabs()[0].getAttribute("aria-selected"), "true", "UI selected");
  });

  test("P: reorder with alt+arrows keeps the active profile", () => {
    withProfiles(["Casa", "Viaje"]);
    tkey(ptabs()[0], "ArrowRight", { altKey: true });
    eq(lastSave().configs.map((c) => c.name).join("|"), "Casa|Trabajo <b>x</b>|Viaje", "moved right");
    eq(lastSave().active, 2, "active still Trabajo");
    tkey(ptabs()[1], "ArrowLeft", { altKey: true });
    eq(lastSave().configs[0].name, "Trabajo <b>x</b>", "moved back");
    eq(lastSave().active, 1, "active follows");
    const n = byAction("save").length;
    tkey(ptabs()[0], "ArrowLeft", { altKey: true });
    eq(byAction("save").length, n, "no move past the start");
  });

  test("P: profile drag is ignored by slots, app drag ignored by tabs", () => {
    withProfiles(["Casa"]);
    const d = dt();
    ptabs()[1].ondragstart({ dataTransfer: d });
    let before = JSON.stringify(document.querySelector('.slot').outerHTML + document.querySelectorAll('.slot').length);
    slotOf("LC49G95T", 2).ondrop({ preventDefault() {}, dataTransfer: Object.assign(d, { types: ["application/x-trisplit-profile"] }) });
    eq(JSON.stringify(document.querySelector('.slot').outerHTML + document.querySelectorAll('.slot').length), before, "slots untouched by a profile drop");
    ptabs()[1].ondragend();
    fresh();
    const names = pnames().join("|");
    ptabs()[0].ondrop({ preventDefault() {}, stopPropagation() {}, dataTransfer: { types: ["text/plain"], getData: () => JSON.stringify({ app: "Slack", tray: true }) } });
    eq(pnames().join("|"), names, "tab order untouched by an app drop");
  });

  test("P: menu: move left/right, disabled at the edges", () => {
    withProfiles(["Casa", "Viaje"]);
    openMenu();
    eq(menuItem("Mover a la izquierda").disabled, true, "left disabled on first");
    eq(menuItem("Mover a la derecha").disabled, false, "right enabled");
    menuItem("Mover a la derecha").click();
    eq(lastSave().configs.map((c) => c.name).join("|"), "Casa|Trabajo <b>x</b>|Viaje", "moved");
    eq(document.getElementById("profmenu").hidden, true, "menu closed");
  });

  test("P: menu: Eliminar needs 2 clicks, disabled with one profile", () => {
    fresh();
    openMenu();
    eq(menuItem("Eliminar").disabled, true, "disabled with 1");
    esc();
    eq(document.getElementById("profmenu").hidden, true, "Esc closes the menu");
    eq(byAction("close").length, 0, "Esc did not close the window");
    withProfiles(["Casa"]);
    openMenu();
    const delItem = document.querySelector("#profmenu .del-item");
    delItem.click();
    eq(byAction("save").length, 0, "first click only arms");
    delItem.click();
    eq(lastSave().configs.length, 1, "deleted");
    eq(ptabs().length, 1, "one tab left");
    openMenu();
    eq(menuItem("Eliminar").disabled, true, "disabled again");
  });

  test("P: menu closes on outside click; right-click on a tab opens it on that profile", () => {
    withProfiles(["Casa"]);
    openMenu();
    document.body.dispatchEvent(new Event("pointerdown", { bubbles: true }));
    eq(document.getElementById("profmenu").hidden, true, "outside click closes");
    ptabs()[1].oncontextmenu({ preventDefault() {}, clientX: 10, clientY: 10 });
    eq(document.getElementById("profmenu").hidden, false, "context menu open");
    eq(lastSave().active, 2, "right-clicked tab became active");
  });

  test("P: a push arriving mid-rename keeps the input and its typed text", () => {
    withProfiles(["Casa"]);
    ptabs()[0].ondblclick();
    const inp = document.querySelector("#profiles input.tab-edit");
    inp.value = "Escribiendo";
    const s2 = JSON.parse(JSON.stringify(FIXTURE)); s2.configs[0].name = "DesdeMotor";
    window.trisplitSetState(s2);
    assert(inp.isConnected && document.querySelector("#profiles input.tab-edit") === inp, "same input survives");
    eq(inp.value, "Escribiendo", "typed text kept");
    inp.value = "Final"; tkey(inp, "Enter");
    eq(pnames()[0], "Final", "commit applies on top");
    // cancel path applies the parked push
    ptabs()[0].ondblclick();
    window.trisplitSetState(s2);
    esc(document.querySelector("#profiles input.tab-edit"));
    eq(pnames()[0], "DesdeMotor", "parked push applied after cancel");
  });

  test("P: a push while the menu is open is parked until it closes", () => {
    withProfiles(["Casa"]);
    openMenu();
    const s2 = JSON.parse(JSON.stringify(FIXTURE)); s2.configs[0].name = "DesdeMotor";
    window.trisplitSetState(s2);
    eq(document.getElementById("profmenu").hidden, false, "menu still open");
    esc();
    eq(pnames()[0], "DesdeMotor", "applied after close");
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
