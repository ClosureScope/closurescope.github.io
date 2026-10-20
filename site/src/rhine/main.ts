import { BlogReader } from "./blog-reader";
import "./blog.css";
import { createRollingClock } from "./rolling-clock";
import { InspectionOverlay } from "./inspection-overlay";
import "./decryption.css";
import { escapeHtml } from "./html";
import {
  normalizeQuality,
  qualityPresets,
  type QualityPreset,
  type RenderQuality,
} from "./render-quality";
import { qualityMarkup, syncQualityUI } from "./quality-settings";
import { superPerformanceQuality, wallpaperQuality } from "./wallpaper-quality";
import "@kitlangton/rolling-number/styles.css";
import "./style.css";
import "./quality-settings.css";
import "./responsive.css";
import { viewportLayout } from "./viewport-layout";
import { assetUrl } from "./asset-url";
import { pwaSettingsMarkup } from "./pwa";
import {
  createRollingNumber,
  createRollingText,
} from "@kitlangton/rolling-number";
import { ArchiveScene } from "./scene";
import { ContentTransition, SurfaceTransition } from "./ui-transitions";
import { wrap, type ArchiveNavigation } from "./archive-loop";
import {
  records,
  categories,
  archiveColumns,
  columnFiles,
  fileLocation,
} from "./data";
import { TerminalAudio } from "./audio";
import { audioSettingsMarkup } from "./audio-settings";
import {
  createMotionPreferences,
  fullMotion,
  motionEnabled,
  motionPresetFor,
  motionSettingsMarkup,
  motionSummary,
  reducedMotion,
  type MotionKey,
  type MotionPreset,
  type StoredMotion,
} from "./motion-preferences";
import {
  isWallpaper,
  wallpaperHost,
  wallpaperFrame,
  type WallpaperProperties,
} from "./wallpaper";
import "./wallpaper.css";
import { Workbench } from "./workbench";
let workbench: Workbench | undefined;
import { ArchivePlayground } from "./archive-playground";
import { paintTheme, themeSettingsMarkup } from "./theme-ui";
let playground: ArchivePlayground | undefined;
import { WallpaperEffects } from "./wallpaper-effects";
import { WallpaperBackground } from "./wallpaper-background";
import { enableGamepad, onInputDevice } from "./gamepad";
let wallpaperEffects: WallpaperEffects | undefined;

const $ = <T extends HTMLElement = HTMLElement>(selector: string) =>
  document.querySelector<T>(selector)!;
import { brandHeading } from "./brand";

$("#stage").innerHTML = `
  <div id="three-scene" class="three-scene"></div>
  <div class="scene-atmosphere archive-atmosphere"></div>
  <header class="brand">${brandHeading}</header>
  <nav class="system-nav" aria-label="系统导航">
    <button data-action="search"><span class="nav-glyph">⌕</span> DIRECTORY <span class="key">/</span></button>
    <button class="settings-button" data-action="settings" aria-label="系统设置" title="系统设置"><span class="settings-glyph" aria-hidden="true">◷</span><span class="settings-label">设置</span></button>
  </nav>
  <svg id="inspection-marks" viewBox="0 0 1920 1080" aria-hidden="true"><path id="inspection-lines"/><g id="inspection-corners"></g><circle id="inspection-point" r="1.8"/></svg>
  <div id="inspection-text" aria-hidden="true">CONFIDENTIALITY:<strong>GENERAL BUSINESS USE</strong></div>
  <section id="archive-ui" class="archive-ui" aria-label="文章选择">
    <div class="archive-callout"><button class="file-title" data-action="open"><span id="selected-title">${escapeHtml(records[0].title)}</span><span class="file-open" aria-hidden="true">↗</span></button><div class="callout-rule"><i></i></div><button class="read-file" data-action="open">ACCESS FILE <span>→</span></button></div>
    <div id="hover-label" class="hover-label" hidden><span id="hover-title"></span></div>
    <div class="archive-navigation"><button data-action="prev" aria-label="上一篇文章">↑</button><div id="file-ticks" class="file-ticks"></div><button data-action="next" aria-label="下一篇文章">↓</button></div>
    <div class="column-navigation"><button data-action="column-prev" aria-label="上一列">←</button><div><span id="column-number">COLUMN <span id="column-index">01</span> / <span id="column-total"></span></span><strong id="column-name">${escapeHtml(records[0].category)}</strong></div><button data-action="column-next" aria-label="下一列">→</button></div>
    <div class="archive-hint"><kbd>←</kbd> <kbd>→</kbd> 切换列 <span>／</span> <kbd>↑</kbd> <kbd>↓</kbd> 前后文章 <span>／</span> <kbd>ENTER</kbd> 读取</div>
  </section>
  <footer class="system-footer">${isWallpaper ? '<button type="button" class="three-toggle" data-action="toggle-three" aria-pressed="true" title="卸载三维模型，保留 2D 界面">3D 开启</button>' : ""}<span class="footer-clock">ClosureScope <i>／</i> <span id="clock">00:00:00</span></span></footer>
  <div id="pwa-update-notice" class="pwa-update-notice" role="status" hidden><span>新版本已就绪</span><button data-pwa-action="update">更新并重启 ↻</button></div>
  <div id="modal-root"></div><div id="toast" class="toast" role="status"></div>
  <div id="loading" class="archive-loading" role="status">LOADING ARTICLES…</div>
`;

$("#stage").dataset.mode = "archive";

type Mode = "archive" | "detail";
let mode: Mode = "archive", selected = 0, ready = false;
let modal: "search" | "settings" | null = null,
  searchQuery = "",
  filter = "全部文章";
let toastTimer: ReturnType<typeof setTimeout>;
let previousFocus: HTMLElement | null = null;
let modalTransition: SurfaceTransition | undefined;
let modalClosing = false;
let modalSiblings: { node: HTMLElement; inert: boolean }[] = [];
function readLocal<T>(key: string, fallback: T): T {
  try {
    return JSON.parse(localStorage.getItem(key) ?? "null") ?? fallback;
  } catch {
    return fallback;
  }
}
const storedPrefs = readLocal<
  Partial<{
    sound: boolean;
    music: boolean;
    soundVolume: number;
    musicVolume: number;
    reduced: boolean;
    quality: boolean;
    rendering: RenderQuality;
    superPerformance: boolean;
    colorTheme: "light" | "dark";
    motion: StoredMotion;
    motionPreset: MotionPreset;
  }>
>("closurescope-rhine-settings", {});
const initialMotion = createMotionPreferences(
  storedPrefs.motion,
  storedPrefs.reduced ??
    (storedPrefs.motion === undefined
      ? matchMedia("(prefers-reduced-motion: reduce)").matches
      : undefined),
);
const initialMotionPreset = motionPresetFor(initialMotion);
const prefs = {
  sound: storedPrefs.sound ?? true,
  music: storedPrefs.music ?? storedPrefs.sound ?? true,
  soundVolume: storedPrefs.soundVolume ?? 0.55,
  musicVolume: storedPrefs.musicVolume ?? 0.5,
  motion: initialMotion,
  motionPreset: initialMotionPreset,
  quality: storedPrefs.quality ?? true,
  superPerformance: storedPrefs.superPerformance ?? false,
  rendering: normalizeQuality(
    storedPrefs.rendering,
    storedPrefs.quality !== false,
  ),
  colorTheme: storedPrefs.colorTheme === "dark" ? "dark" : "light",
};
const motionActive = (key: MotionKey) => motionEnabled(prefs.motion, key);
const motionIsReduced = () =>
  Object.values(prefs.motion).every((value) => !value);
paintTheme(prefs.colorTheme === "dark" ? 1 : 0);
const rollingMotion = {
  duration: 460,
  motionBlur: true,
  animated: motionActive("rollingNumbers"),
};
const updateFooterClock = createRollingClock($("#clock"));
const numberOptions = {
  ...rollingMotion,
  locales: "en-US",
  format: { minimumIntegerDigits: 2, useGrouping: false },
};
const columnCounter = createRollingNumber($("#column-index"), {
  ...numberOptions,
  value: 1,
});
const textOptions = {
  ...rollingMotion,
  animated: motionActive("rollingText"),
  transition: "direct" as const,
  stagger: "none" as const,
};
const columnTitle = createRollingText($("#column-name"), {
  ...textOptions,
  text: $("#column-name").textContent ?? "",
});
const hoverTitle = createRollingText($("#hover-title"), {
  ...textOptions,
  text: "",
});
const rollingTitles = [columnTitle, hoverTitle];
const titleTransition = new ContentTransition();
const audio = new TerminalAudio();
let musicSuppressed = false;
function configureAudio() {
  audio.configure({ ...prefs, music: prefs.music && !musicSuppressed });
}
configureAudio();
let started = false;
const loading = $("#loading");
$("#viewport").append(loading);
$("#stage").inert = true;
let scene: ArchiveScene | undefined;
let threeState: "on" | "closing" | "off" | "loading" = "on";
let resumeCell: { lane: number; row: number } | undefined;
let resumeSelection = -1;
const columnMemory = archiveColumns.map((_, lane) => columnFiles(lane)[0]);
function saveAudioPrefs() {
  try {
    localStorage.setItem("closurescope-rhine-settings", JSON.stringify(prefs));
  } catch {}
  configureAudio();
}
function superPerformanceEnabled() {
  return isWallpaper
    ? wallpaperHost()?.properties.superperformance?.value === true
    : prefs.superPerformance;
}
function effectiveRenderQuality() {
  return superPerformanceEnabled() ? superPerformanceQuality : prefs.rendering;
}
function savePrefs() {
  saveAudioPrefs();
  if (!motionActive("rollingText")) {
    rollingTitles.forEach((title) => title.finish());
    titleTransition.finish();
  }
  if (!motionActive("rollingNumbers"))
    columnCounter.finish();
  if (!motionActive("surfaceTransitions")) {
    modalTransition?.finish();
  }
  scene?.setMotion(prefs.motion);
  scene?.setTheme(
    prefs.colorTheme === "dark",
    !motionActive("surfaceTransitions") || !started,
  );
  document
    .querySelectorAll<HTMLElement>("[data-color-theme]")
    .forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.colorTheme === prefs.colorTheme),
      ),
    );
  scene?.setSuperPerformance(superPerformanceEnabled());
  scene?.setQuality(effectiveRenderQuality());
  syncQualityUI(prefs.rendering);
  updateQualitySummary();
  rollingTitles.forEach((title) =>
    title.update({
      animated: motionActive("rollingText") && mode === "archive",
    }),
  );
  columnCounter.update({
    animated: motionActive("rollingNumbers") && mode === "archive",
  });
  $("#stage").classList.toggle("reduce-motion", motionIsReduced());
  $("#stage").classList.toggle(
    "reduce-surfaces",
    !motionActive("surfaceTransitions"),
  );
  workbench?.setMotion(prefs.motion);
  updateFooterClock(new Date(), motionActive("rollingNumbers"));
  syncWallpaperBackground();
}
let previousLayout = "";
function fit() {
  const stage = $("#stage");
  const viewport = $("#viewport");
  const coarse = matchMedia("(pointer: coarse)").matches;
  const { width, height, scale, kind } = viewportLayout(
    viewport.clientWidth, viewport.clientHeight, coarse,
  );
  stage.style.width = `${width}px`;
  stage.style.height = `${height}px`;
  stage.style.transform = `translate(-50%, -50%) scale(${scale})`;
  stage.dataset.layout = kind;
  stage.dataset.touch = String(coarse);
  stage.style.setProperty("--stage-scale", String(scale));
  // The software keyboard resizes dialogs without recomposing the 3D scene.
  const visible = window.visualViewport;
  const stageTop = (viewport.clientHeight - height * scale) / 2;
  stage.style.setProperty(
    "--modal-top",
    `${Math.max(0, (visible?.offsetTop ?? 0) - stageTop) / scale}px`,
  );
  stage.style.setProperty(
    "--modal-height",
    `${Math.min(height, (visible?.height ?? viewport.clientHeight) / scale)}px`,
  );
  $("#viewport").style.setProperty("--scale", String(scale));
  const marks = document.querySelector("#inspection-marks");
  marks?.setAttribute("viewBox", `0 0 ${width} ${height}`);
  const layoutKey = JSON.stringify([
    width,
    height,
    scale,
    kind,
    devicePixelRatio,
  ]);
  if (layoutKey !== previousLayout) {
    previousLayout = layoutKey;
    scene?.resize();
  }
  updateQualitySummary();

}
window.addEventListener("resize", fit);
window.visualViewport?.addEventListener("resize", fit);
window.visualViewport?.addEventListener("scroll", fit);
matchMedia("(pointer: coarse)").addEventListener("change", fit);
fit();
// Ticks are rebuilt for the selected column; columns need not have equal lengths.
const blogReader = new BlogReader(
  () => setMode("archive"),
  () => { setMode("archive"); openModal("search"); },
);
let renderedColumn = -1;

function setMode(next: Mode) {
  if (workbench?.enabled && next === "detail") next = "archive";
  const previousMode = mode;
  rollingTitles.forEach(title => title.update({
    animated: motionActive("rollingText") && next === "archive",
  }));
  if (next !== "archive") {
    rollingTitles.forEach(title => title.finish());
    $("#hover-label").hidden = true;
  }
  mode = next;
  audio.setScene(next);
  $("#stage").dataset.mode = next;
  $("#stage").inert = next === "detail";
  workbench?.syncVisibility();
  syncWallpaperBackground();
  if (previousMode !== next) fit();
  $("#archive-ui").inert = next !== "archive" || Boolean(modal) || Boolean(workbench?.enabled);
  $("#archive-ui").setAttribute("aria-hidden", String(next !== "archive" || Boolean(workbench?.enabled)));
  $(".system-nav").inert = Boolean(modal);
  $(".system-footer").inert = Boolean(modal);
  if (next === "detail") {
    const record = records[selected];
    blogReader.open(record.source, record.title);
  }
  blogReader.setVisible(next === "detail");
  if (previousMode === "detail" && next === "archive" && !modal)
    $(".read-file").focus({ preventScroll: true });
}
function select(index: number, navigation?: ArchiveNavigation) {
  selected = (index + records.length) % records.length;
  columnMemory[fileLocation(selected).lane] = selected;
  if (mode === "detail") setMode("archive");
  scene?.select(selected, navigation);
  updateSelection(navigation);
  const columnMove =
    navigation && "axis" in navigation && navigation.axis === "lane";
  audio.play(
    columnMove ? "column" : "tick",
    columnMove ? navigation.direction * 0.45 : 0,
  );
}
function stepFile(direction: number) {
  const files = columnFiles(fileLocation(selected).lane);
  if (files.length < 2) return;
  select(
    files[(files.indexOf(selected) + direction + files.length) % files.length],
    { axis: "row", direction },
  );
}
function stepColumn(direction: number) {
  const lane = fileLocation(selected).lane;
  if (archiveColumns.length < 2) return;
  const next = wrap(lane + direction, archiveColumns.length);
  select(columnMemory[next], { axis: "lane", direction });
}
function updateSelection(navigation?: ArchiveNavigation) {
  const r = records[selected];
  const { lane } = fileLocation(selected);
  const files = columnFiles(lane);
  const title = $("#selected-title");
  if (title.textContent !== r.title) {
    title.textContent = r.title;
    titleTransition.reveal(title, !started || !motionActive("rollingText"));
  }
  const direction = navigation && "axis" in navigation
    ? navigation.direction > 0 ? "up" : "down"
    : "auto";
  columnCounter.update({
    value: lane + 1,
    animated: motionActive("rollingNumbers") && mode === "archive",
    direction:
      navigation && "axis" in navigation && navigation.axis === "lane"
        ? direction
        : "auto",
  });
  columnTitle.update({
    text: archiveColumns[lane],
    animated: motionActive("rollingText") && mode === "archive",
  });
  $("#column-total").textContent = String(archiveColumns.length).padStart(2, "0");
  for (const action of ["column-prev", "column-next"])
    $<HTMLButtonElement>(`[data-action="${action}"]`).disabled = archiveColumns.length < 2;
  for (const action of ["prev", "next"])
    $<HTMLButtonElement>(`[data-action="${action}"]`).disabled = files.length < 2;
  if (renderedColumn !== lane) {
    renderedColumn = lane;
    $("#file-ticks").innerHTML = files.map(index => {
      const record = records[index];
      return `<button data-select="${index}" aria-label="选择文章 ${escapeHtml(record.title)}" title="${escapeHtml(record.title)}"></button>`;
    }).join("");
  }
  const ticks = $("#file-ticks");
  ticks.querySelectorAll<HTMLButtonElement>("button").forEach(button => {
    const active = Number(button.dataset.select) === selected;
    button.classList.toggle("selected", active);
    button.setAttribute("aria-pressed", String(active));
    if (active) {
      if (button.offsetLeft < ticks.scrollLeft) ticks.scrollLeft = button.offsetLeft;
      else if (button.offsetLeft + button.offsetWidth > ticks.scrollLeft + ticks.clientWidth)
        ticks.scrollLeft = button.offsetLeft + button.offsetWidth - ticks.clientWidth;
    }
  });
}
function openFile() {
  if (!ready) return;
  closeModal(() => {
    setMode("detail");
    audio.play("open");
  });
}
function notify(message: string) {
  clearTimeout(toastTimer);
  $("#toast").textContent = message;
  $("#toast").classList.add("visible");
  toastTimer = setTimeout(() => $("#toast").classList.remove("visible"), 2600);
}

function openModal(kind: NonNullable<typeof modal>) {
  if (!ready) return;
  if (!modal) {
    previousFocus = document.activeElement as HTMLElement;
    modalSiblings = [...$("#stage").children]
      .filter(
        (node): node is HTMLElement =>
          node instanceof HTMLElement && node.id !== "modal-root",
      )
      .map((node) => ({ node, inert: node.inert }));
    modalSiblings.forEach(({ node }) => (node.inert = true));
  }
  modalClosing = false;
  modal = kind;
  searchQuery = "";
  filter = "全部文章";
  audio.play("page-open");
  renderModal();
}
function closeModal(afterClose?: () => void) {
  if (!modal) {
    afterClose?.();
    return;
  }
  if (modalClosing) return;
  modalClosing = true;
  audio.play("page-close");
  modalTransition!.hide(!motionActive("surfaceTransitions"), () => {
    modal = null;
    modalClosing = false;
    $("#modal-root").replaceChildren();
    modalTransition = undefined;
    modalSiblings.forEach(({ node, inert }) => (node.inert = inert));
    modalSiblings = [];
    $("#archive-ui").inert = mode !== "archive" || Boolean(workbench?.enabled);
    previousFocus?.focus({ preventScroll: true });
    afterClose?.();
  });
}
function renderModal() {
  if (!modal) return;
  modalTransition?.dispose();
  $("#modal-root").innerHTML =
    `<div class="modal-backdrop"><section class="terminal-modal ${modal === "settings" ? "settings-modal" : ""}" role="dialog" aria-modal="true" aria-label="${modal === "settings" ? "系统设置" : "文章检索"}"><div class="modal-top"><span>ClosureScope / ${modal === "settings" ? "SYSTEM PREFERENCES" : "DIRECTORY"}</span><button data-action="close-modal" aria-label="关闭窗口">CLOSE <span>×</span></button></div>${modal === "settings" ? settingsMarkup() : `<h2>DIRECTORY<small>文章检索</small></h2><div class="search-field"><span>⌕</span><input id="archive-search" type="search" autocomplete="off" placeholder="输入文章标题、文件名或分类" aria-label="检索文章"/><span class="key">ESC</span></div><div class="category-filters">${categories.map((c, i) => `<button data-filter="${escapeHtml(c)}" class="${i === 0 ? "active" : ""}">${escapeHtml(c)}</button>`).join("")}</div><div class="result-header"><span>FILE / 文章</span><span>CATEGORY / 分类</span></div><div id="search-results" class="search-results"></div><div class="modal-bottom"><span id="result-count"></span><span>INTERNAL DATABASE <i>●</i> CONNECTED</span></div>`}</section></div>`;
  const backdrop = $(".modal-backdrop");
  backdrop.hidden = true;
  modalTransition = new SurfaceTransition(backdrop, $(".terminal-modal"));
  modalTransition.show(!motionActive("surfaceTransitions"));
  if (modal === "settings") updateQualitySummary();
  if (modal !== "settings") {
    renderResults();
    requestAnimationFrame(() => {
      if (backdrop.isConnected && !modalClosing) $("#archive-search").focus();
    });
  } else
    requestAnimationFrame(() => {
      if (backdrop.isConnected && !modalClosing)
        $('[data-action="close-modal"]').focus();
    });
  $("#modal-root")
    .querySelector(".modal-backdrop")
    ?.addEventListener("click", (e) => {
      if (e.target === e.currentTarget) closeModal();
    });
}
function renderResults() {
  const results = records
    .map((r, i) => ({ r, i }))
    .filter(
      ({ r }) =>
        (filter === "全部文章" || r.category === filter) &&
        `${r.id} ${r.title} ${r.category}`
          .toLowerCase()
          .includes(searchQuery.toLowerCase()),
    );
  $("#search-results").innerHTML = results.length
    ? results
        .map(
          ({ r, i }) =>
            `<button class="result-row" data-result="${i}"><span class="result-name"><span>${escapeHtml(r.title)}<small>${escapeHtml(r.category)}</small></span></span><span>${escapeHtml(r.department)}</span></button>`,
        )
        .join("")
    : `<div class="empty-results"><span>∅</span><strong>没有匹配的文章</strong><p>尝试其他文章标题、文件名，或切换分类。</p><button data-action="reset-search">重置检索 →</button></div>`;
  $("#result-count").textContent =
    `${String(results.length).padStart(2, "0")} RECORDS FOUND`;
}
function updateQualitySummary() {
  const summary = document.querySelector("#quality-summary");
  if (!summary) return;
  if (!scene) {
    summary.textContent = "3D 已关闭 · 三维模型与渲染资源已释放";
    return;
  }
  const canvas = scene.renderer.domElement;
  const metrics = JSON.parse(
    canvas.parentElement?.dataset.renderQuality ?? "{}",
  );
  summary.textContent = `${superPerformanceEnabled() ? "超级性能模式已启用 · 画质设置暂被覆盖，关闭后恢复 · " : ""}实际渲染 ${canvas.width} × ${canvas.height} · ${effectiveRenderQuality().antialias === "smaa" ? "SMAA" : "原始抗锯齿"} · 纹理 ${metrics.anisotropy ?? 1}×${metrics.limited ? " · 已达到缓冲上限" : ""}`;
}
function motionPreferenceNoteMarkup() {
  const preset = prefs.motionPreset;
  const allEnabled = Object.values(prefs.motion).every(Boolean);
  return `<div id="motion-preference-note" class="motion-preference-note"><p>${motionSummary(prefs.motion)}</p><span>预设：${preset === "full" ? "完整动画" : preset === "reduced" ? "减少动画" : "自定义"} · 选择会保存在本站</span>${allEnabled ? "" : '<button data-action="enable-motion">启用完整动画</button>'}</div>`;
}
function settingsMarkup() {
  return `<h2>SYSTEM SETTINGS<small>终端偏好设置</small></h2><p class="settings-intro">ClosureScope</p>${isWallpaper ? '<p class="wallpaper-settings-note">每次启动都会读取 Wallpaper Engine 中的设置。在此修改仅对当前运行生效，无法持久保存；如需保留，请在 Wallpaper Engine 的壁纸属性中调整。</p>' : ""}<div class="settings-list">${themeSettingsMarkup(prefs.colorTheme === "dark")}${!isWallpaper ? `<label><div><strong>SUPER PERFORMANCE</strong><span>降低三维画质和渲染分辨率，保留完整动效；关闭后恢复原画质</span></div><input type="checkbox" data-pref="superPerformance" ${prefs.superPerformance ? "checked" : ""}/><i class="toggle"></i></label>` : ""}${workbench?.settingsMarkup() ?? ""}${audioSettingsMarkup(prefs)}</div>${motionPreferenceNoteMarkup()}${motionSettingsMarkup(prefs.motion, prefs.motionPreset)}${qualityMarkup(prefs.rendering)}${pwaSettingsMarkup()}<div class="settings-shortcuts">${isWallpaper ? "<span>DESKTOP CONTROLS</span><p>拖动阵列或点击界面按钮浏览文章。桌面模式下，方向键与滚轮可能无法传入壁纸。</p>" : "<span>KEYBOARD CONTROLS</span><p><kbd>←</kbd><kbd>→</kbd> 切列 <kbd>↑</kbd><kbd>↓</kbd> 选文章 <kbd>ENTER</kbd> 读取 <kbd>/</kbd> 检索 <kbd>ESC</kbd> 返回</p>"}</div><div class="settings-bottom">${!isWallpaper && document.fullscreenEnabled ? '<button data-action="fullscreen">FULLSCREEN <span>↗</span></button>' : ""}</div><div class="modal-bottom"><span>ClosureScope · 使用 MiSans 字体（小米） <a href="${assetUrl("fonts/MiSans-license.pdf")}" target="_blank" rel="noopener">字体许可</a></span></div>`;
}

document.addEventListener("input", (e) => {
  const slider = e.target as HTMLInputElement;
  if (slider.dataset.quality) {
    const output = document.querySelector<HTMLOutputElement>(
      `[data-quality-output="${slider.dataset.quality}"]`,
    );
    if (output) output.value = `${slider.value}%`;
  }
  const volume = e.target as HTMLInputElement;
  if (
    volume.dataset.volume === "musicVolume" ||
    volume.dataset.volume === "soundVolume"
  ) {
    prefs[volume.dataset.volume] = Number(volume.value) / 100;
    volume
      .closest("label")
      ?.querySelector("output")
      ?.replaceChildren(`${volume.value}%`);
    saveAudioPrefs();
  }
  if ((e.target as HTMLElement).id === "archive-search") {
    searchQuery = (e.target as HTMLInputElement).value;
    renderResults();
  }
});
document.addEventListener("change", (e) => {
  const el = e.target as HTMLInputElement;
  if (el.id === "quality-preset" && Object.hasOwn(qualityPresets, el.value)) {
    prefs.rendering = { ...qualityPresets[el.value as QualityPreset] };
    savePrefs();
  } else if (el.dataset.quality) {
    const key = el.dataset.quality as keyof RenderQuality;
    prefs.rendering = normalizeQuality({
      ...prefs.rendering,
      [key]: key === "antialias" ? el.value : Number(el.value),
    });
    savePrefs();
  }
  if (el.dataset.pref) {
    const key = el.dataset.pref;
    if (
      key === "sound" ||
      key === "music" ||
      key === "quality" ||
      key === "superPerformance"
    )
      prefs[key] = el.checked;
    if (key === "sound" || key === "music") saveAudioPrefs();
    else savePrefs();
    audio.play("confirm");
  }
  if (el.dataset.motion) {
    const key = el.dataset.motion as MotionKey;
    prefs.motion[key] = el.checked;
    prefs.motionPreset = motionPresetFor(prefs.motion);
    savePrefs();
    const motionRoot = $("#motion-settings");
    const advancedOpen =
      motionRoot.querySelector<HTMLDetailsElement>(".motion-advanced")?.open ??
      false;
    const settingsPanel = motionRoot.closest<HTMLElement>(".settings-modal");
    const scrollTop = settingsPanel?.scrollTop ?? 0;
    motionRoot.outerHTML = motionSettingsMarkup(
      prefs.motion,
      prefs.motionPreset,
    );
    $("#motion-preference-note").outerHTML = motionPreferenceNoteMarkup();
    $("#motion-settings").querySelector<HTMLDetailsElement>(
      ".motion-advanced",
    )!.open = advancedOpen;
    requestAnimationFrame(() => {
      if (settingsPanel) settingsPanel.scrollTop = scrollTop;
      document
        .querySelector<HTMLInputElement>(`[data-motion="${key}"]`)
        ?.focus({ preventScroll: true });
    });
    notify(el.checked ? "已启用此动画" : "已关闭此动画");
    audio.play("confirm");
  }
});
document.addEventListener("click", (e) => {
  const themeButton = (e.target as Element).closest<HTMLElement>(
    "[data-color-theme]",
  );
  if (themeButton) {
    prefs.colorTheme =
      themeButton.dataset.colorTheme === "dark" ? "dark" : "light";
    savePrefs();
    return;
  }
  if (!started) return;
  if (modalClosing) return;
  const el = (e.target as Element).closest<HTMLElement>("button");
  if (!el) return;
  if (el.dataset.action === "motion-preset") {
    const preset = el.dataset.preset;
    if (preset !== "full" && preset !== "reduced") return;
    prefs.motionPreset = preset;
    prefs.motion = preset === "full" ? fullMotion() : reducedMotion();
    savePrefs();
    renderModal();
    requestAnimationFrame(() =>
      document
        .querySelector<HTMLButtonElement>(
          `[data-action="motion-preset"][data-preset="${prefs.motionPreset}"]`,
        )
        ?.focus({ preventScroll: true }),
    );
    audio.play("confirm");
    return;
  }
  if (el.dataset.select) {
    select(Number(el.dataset.select));
    return;
  }
  if (el.dataset.result) {
    const index = Number(el.dataset.result);
    closeModal(() => {
      select(index);
      openFile();
    });
    return;
  }
  if (el.dataset.filter) {
    filter = el.dataset.filter;
    document
      .querySelectorAll("[data-filter]")
      .forEach((b) =>
        b.classList.toggle(
          "active",
          (b as HTMLElement).dataset.filter === filter,
        ),
      );
    renderResults();
    return;
  }
  const action = el.dataset.action;
  if (action === "toggle-three") {
    void toggleThree();
    return;
  }
  if (action === "sound-preview") audio.play("confirm");
  if (action === "prev") stepFile(-1);
  if (action === "next") stepFile(1);
  if (action === "column-prev") stepColumn(-1);
  if (action === "column-next") stepColumn(1);
  if (action === "open") openFile();
  if (action === "back") {
    setMode("archive");
    audio.play("back");
  }
  if (action === "search" || action === "settings") {
    if (mode === "detail") setMode("archive");
    el.focus({ preventScroll: true });
    openModal(action);
  }
  if (action === "close-modal") closeModal();
  if (action === "reset-search") {
    modal = "search";
    searchQuery = "";
    filter = "全部文章";
    renderModal();
  }
  if (action === "enable-motion") {
    prefs.motion = fullMotion();
    prefs.motionPreset = "full";
    savePrefs();
  }
  if (action === "fullscreen" && document.fullscreenEnabled) {
    if (document.fullscreenElement) void document.exitFullscreen();
    else
      void document.documentElement
        .requestFullscreen()
        .catch(() => notify("请使用浏览器的全屏快捷键 F11"));
  }
});
document.addEventListener("keydown", (e) => {
  if (!started) return;
  if (playground?.active && !modal) {
    if (e.key === "Escape") {
      e.preventDefault();
      playground.stop();
    } else if (
      [
        "ArrowLeft",
        "ArrowRight",
        "ArrowUp",
        "ArrowDown",
        "Enter",
        "/",
      ].includes(e.key) &&
      !(e.target instanceof HTMLButtonElement)
    )
      e.preventDefault();
    return;
  }
  if (modalClosing) {
    e.preventDefault();
    return;
  }
  const typing = e.target instanceof HTMLInputElement;
  if (e.key === "Escape") {
    if (modal) closeModal();
    else if (mode === "detail") {
      const sound = "back";
      setMode("archive");
      audio.play(sound);
    }
    return;
  }
  if (modal && e.key === "Tab") {
    const focusables = [
      ...$("#modal-root").querySelectorAll<HTMLElement>(
        'a[href],button:not(:disabled),input:not(:disabled),select:not(:disabled),summary,[tabindex="0"]',
      ),
    ];
    const visible = focusables.filter(
      (el) =>
        el.tabIndex >= 0 &&
        !el.matches(":disabled") &&
        el.getClientRects().length > 0,
    );
    const first = visible[0],
      last = visible.at(-1);
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last?.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first?.focus();
    }
    return;
  }
  if (typing || modal || !ready) return;
  if (e.key === "/") {
    e.preventDefault();
    if (mode === "detail") setMode("archive");
    openModal("search");
  }
  if (mode === "detail") return;
  if (e.key === "ArrowLeft") {
    e.preventDefault();
    stepColumn(-1);
  }
  if (e.key === "ArrowRight") {
    e.preventDefault();
    stepColumn(1);
  }
  if (["ArrowUp", "ArrowDown"].includes(e.key)) {
    e.preventDefault();
    stepFile(e.key === "ArrowUp" ? -1 : 1);
  }
  if (
    e.key === "Enter" &&
    (document.activeElement === document.body ||
      ["prev", "next", "column-prev", "column-next"].includes(
        (document.activeElement as HTMLElement)?.dataset.action ?? "",
      ) ||
      (document.activeElement as HTMLElement)?.dataset.select)
  ) {
    e.preventDefault();
    if (mode === "archive") openFile();
  }
});

const inspectionOverlay = new InspectionOverlay();
let lastTime = 0,
  frameCount = 0,
  frameStart = performance.now(),
  fps = 0;
function frame(ms: number) {
  if (!wallpaperFrame(ms)) {
    requestAnimationFrame(frame);
    return;
  }
  if (document.hidden) {
    requestAnimationFrame(frame);
    return;
  }
  workbench?.tick();
  const time = ms / 1000;
  const theme = scene?.themeAmount ?? (prefs.colorTheme === "dark" ? 1 : 0);
  paintTheme(theme);
  playground?.tick(time);
  wallpaperEffects?.update(
    time,
    motionIsReduced(),
    motionActive("pointerParallax"),
  );
  if (mode === "archive") scene?.update(time);
  if (threeState === "closing" && scene?.presentationHidden) releaseThree();
  playground?.position();
  $("#stage").style.setProperty(
    "--detail-shade",
    "0",
  );
  const currentScene = scene;
  if (currentScene)
    inspectionOverlay.render(
      currentScene.decryptionFrame,
      (x, y) => currentScene.projectCard(x, y),
      false,
      motionActive("modelDecryption"),
    );
  if (Math.floor(time) !== lastTime) {
    lastTime = Math.floor(time);
    updateFooterClock(new Date(), motionActive("rollingNumbers"));
  }
  frameCount++;
  if (ms - frameStart > 1000) {
    fps = (frameCount * 1000) / (ms - frameStart);
    frameStart = ms;
    frameCount = 0;
    $("#three-scene").dataset.fps = String(Math.round(fps));
    $("#three-scene").dataset.renderStats = JSON.stringify(
      scene?.getStats() ?? { loaded: false, drawCalls: 0, triangles: 0 },
    );
  }
  requestAnimationFrame(frame);
}
function bindScene(scene: ArchiveScene, cell?: { lane: number; row: number }) {
  scene.select(selected, cell ? { cell } : undefined);
  scene.onSelect = (i, cell) => {
    if (mode !== "archive" || modal) return;
    select(i, cell ? { cell } : undefined);
  };
  scene.onNavigate = (axis, direction) => {
    if (mode !== "archive" || modal) return;
    if (axis === "lane") stepColumn(direction);
    else stepFile(direction);
  };
  scene.onHover = (i) => {
    const label = $("#hover-label");
    if (i === null) {
      label.hidden = true;
      hoverTitle.finish();
      return;
    }
    const animated = motionActive("rollingText") && mode === "archive";
    hoverTitle.update({
      text: records[i].title,
      animated: !label.hidden && animated,
    });
    label.hidden = false;
    // Prepare the first visible value so the next hover can animate immediately.
    hoverTitle.update({ animated });
  };
}
function syncThreeButton() {
  $("#stage").dataset.threeState = threeState;
  syncWallpaperBackground();
  const button = document.querySelector<HTMLButtonElement>(
    '[data-action="toggle-three"]',
  );
  if (!button) return;
  button.textContent =
    threeState === "loading"
      ? "3D 载入中…"
      : threeState === "closing"
        ? "3D 关闭中…"
        : threeState === "off"
          ? "3D 关闭"
          : "3D 开启";
  button.disabled = threeState === "loading";
  button.setAttribute("aria-pressed", String(threeState === "on"));
  button.title =
    threeState === "off"
      ? "重新载入三维模型"
      : threeState === "closing"
        ? "取消关闭，恢复三维画面"
        : "卸载三维模型，保留 2D 界面";
}
function releaseThree() {
  if (!scene) return;
  resumeCell = { ...scene.getStats().selectedCell };
  resumeSelection = selected;
  scene.dispose();
  scene = undefined;
  threeState = "off";
  syncThreeButton();
  $("#hover-label").hidden = true;
  delete $("#three-scene").dataset.renderQuality;
  updateQualitySummary();
}
async function toggleThree() {
  if (!isWallpaper || !ready || threeState === "loading") return;
  if (threeState === "closing") {
    scene?.setPresentationVisible(true, !motionActive("surfaceTransitions"));
    threeState = "on";
    syncThreeButton();
    return;
  }
  if (scene) {
    playground?.stop();
    threeState = "closing";
    syncThreeButton();
    scene.setPresentationVisible(false, !motionActive("surfaceTransitions"));
    if (!motionActive("surfaceTransitions")) releaseThree();
    return;
  }
  threeState = "loading";
  syncThreeButton();
  let next: ArchiveScene | undefined;
  try {
    next = new ArchiveScene($("#three-scene"));
    next.renderer.domElement.style.opacity = "0";
    next.setPresentationVisible(false, true);
    await next.load();
    next.setMode("archive");
    bindScene(next, resumeSelection === selected ? resumeCell : undefined);
    next.revealImmediately();
    scene = next;
    scene.setTheme(prefs.colorTheme === "dark", true);
    scene.setArchiveCoverage(
      wallpaperHost()?.properties.archivecoverage?.value === "extra",
    );
    savePrefs();
    scene.setPresentationVisible(true, !motionActive("surfaceTransitions"));
    threeState = "on";
    syncThreeButton();
  } catch (error) {
    next?.dispose();
    scene = undefined;
    threeState = "off";
    syncThreeButton();
    notify("三维模型载入失败，请点击 3D 关闭重试。");
    console.error(error);
  }
}

async function start() {
  try {
    scene = new ArchiveScene($("#three-scene"));
    scene.setTheme(prefs.colorTheme === "dark", true);
    scene.setArchiveCoverage(wallpaperHost()?.properties.archivecoverage?.value === "extra");
    // Load only the model and fonts needed by the archive, with no entry gate.
    await Promise.all([
      scene.load(),
      document.fonts.load("400 20px MiSans", records[0].title + records[0].category),
      document.fonts.load("700 20px MiSans", "ClosureScope"),
    ]);
    bindScene(scene);
    savePrefs();
    ready = true;
    select(0);
    started = true;
    setMode("archive");
    scene.revealImmediately();
    $("#stage").inert = false;
    loading.remove();
    requestAnimationFrame(frame);
  } catch (error) {
    console.error(error);
    loading.innerHTML = '<span>文章资源未能载入。</span> <button onclick="location.reload()">重新加载 ↻</button>';
  }
}
updateSelection();
const customBackground = isWallpaper
  ? new WallpaperBackground($("#stage"), notify)
  : undefined;
function syncWallpaperBackground(retry = false) {
  customBackground?.update(
    wallpaperHost()?.properties ?? {},
    threeState === "off" || threeState === "loading",
    !motionActive("surfaceTransitions"),
    retry,
  );
}
if (isWallpaper) {
  const apply = (properties: WallpaperProperties) => {
    const theme = properties.colortheme?.value;
    if (theme === "light" || theme === "dark") prefs.colorTheme = theme;
    scene?.setArchiveCoverage(
      properties.archivecoverage?.value === "extra" ||
        wallpaperHost()?.properties.archivecoverage?.value === "extra",
    );
    for (const key of ["sound", "music"] as const)
      if (typeof properties[key]?.value === "boolean")
        prefs[key] = properties[key].value as boolean;
    if (typeof properties.reduced?.value === "boolean") {
      prefs.motion = properties.reduced.value ? reducedMotion() : fullMotion();
      prefs.motionPreset = motionPresetFor(prefs.motion);
    }
    for (const key of ["soundVolume", "musicVolume"] as const) {
      const value = properties[key.toLowerCase()]?.value;
      if (typeof value === "number" && Number.isFinite(value))
        prefs[key] = Math.max(0, Math.min(1, value / 100));
    }
    const qualityProperties = { ...wallpaperHost()?.properties, ...properties };
    if (
      Object.keys(properties).some(
        (key) => key === "renderquality" || key.startsWith("quality"),
      )
    )
      prefs.rendering = wallpaperQuality(qualityProperties, prefs.rendering);
    savePrefs();
    if (
      properties.customwallpaperfile ||
      properties.customwallpaper?.value === true
    )
      syncWallpaperBackground(true);
    // Keep an already-open settings surface in sync without replacing focused controls.
    document
      .querySelectorAll<HTMLInputElement>("[data-pref]")
      .forEach((input) => {
        const key = input.dataset.pref as
          "sound" | "music" | "quality" | "superPerformance";
        if (key in prefs) input.checked = prefs[key];
      });
    document
      .querySelectorAll<HTMLInputElement>("[data-motion]")
      .forEach((input) => {
        input.checked = prefs.motion[input.dataset.motion as MotionKey];
      });
    document
      .querySelectorAll<HTMLElement>('[data-action="motion-preset"]')
      .forEach((button) => {
        button.setAttribute(
          "aria-pressed",
          String(button.dataset.preset === prefs.motionPreset),
        );
      });
    const note = document.querySelector("#motion-preference-note");
    if (note) note.outerHTML = motionPreferenceNoteMarkup();
    for (const key of ["soundVolume", "musicVolume"] as const) {
      const input = document.querySelector<HTMLInputElement>(
        `[data-volume="${key}"]`,
      );
      if (input) {
        input.value = String(Math.round(prefs[key] * 100));
        input
          .closest("label")
          ?.querySelector("output")
          ?.replaceChildren(`${input.value}%`);
      }
    }
  };
  window.addEventListener("rhine-wallpaper-properties", (event) =>
    apply((event as CustomEvent<WallpaperProperties>).detail),
  );
  const pause = () => audio.setHostPaused(wallpaperHost()?.paused ?? false);
  window.addEventListener("rhine-wallpaper-pause", pause);
  apply(wallpaperHost()?.properties ?? {});
  pause();
}
if (isWallpaper) {
  workbench = new Workbench(
    $("#stage"),
    () => {
      if (ready) setMode("archive");
    },
    (lane) => {
      if (ready && !modal) select(columnMemory[lane]);
    },
  );
  workbench.setMotion(prefs.motion);
  playground = new ArchivePlayground(
    $("#stage"),
    () => scene,
    () => ({
      enabled: !!workbench?.enabled && mode === "archive" && ready,
      paused:
        Boolean(modal) ||
        modalClosing ||
        Boolean(wallpaperHost()?.paused) ||
        document.hidden,
      reduced: motionIsReduced(),
    }),
    (value) => {
      musicSuppressed = value;
      configureAudio();
    },
    () => audio.play("tick"),
  );
  wallpaperEffects = new WallpaperEffects($("#stage"), () => scene);
  document.addEventListener("click", (event) => {
    const button = (event.target as Element).closest<HTMLElement>(
      "[data-workbench-mode]",
    );
    if (button)
      closeModal(() => {
        workbench!.setEnabled(button.dataset.workbenchMode === "workbench");
      });
  });
}
void start();
enableGamepad();
const ARCHIVE_HINT: Record<"keyboard" | "gamepad", string> = {
  keyboard: `<kbd>←</kbd> <kbd>→</kbd> 切换列 <span>／</span> <kbd>↑</kbd> <kbd>↓</kbd> 前后文章 <span>／</span> <kbd>ENTER</kbd> 读取`,
  gamepad: `<kbd>LS</kbd> <kbd>DP</kbd> 切换列 / 前后文章 <span>／</span> <kbd>A</kbd> 读取`,
};
onInputDevice((device) => {
  const hint = document.querySelector(".archive-hint");
  if (hint) hint.innerHTML = ARCHIVE_HINT[device];
});
// Deterministic review controls: the running application, never a video surrogate.
Object.assign(window, {
  rhine: {
    archive: () => setMode("archive"),
    detail: () => openFile(),
    select: (i: number) => select(i),
    stats: () => ({
      ...scene?.getStats(),
      threeState,
      fps: Math.round(fps),
      mode,
      ready,
      startup: started ? "started" : "loading",
      motion: { reduced: motionIsReduced(), preset: prefs.motionPreset },
      selected: records[selected].id,
      audio: audio.stats(),
      wallpaper: isWallpaper ? wallpaperHost() : null,
    }),
  },
});
if (import.meta.hot) import.meta.hot.dispose(() => { audio.dispose(); blogReader.dispose(); });
