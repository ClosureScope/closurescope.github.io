import {
  matchingPreset,
  presetLabels,
  type QualityPreset,
  type RenderQuality,
} from "./render-quality";
import { isWallpaper } from "./wallpaper";
import { escapeHtml } from "./html";

function choiceControl(attributes: string, label: string, value: string | number, choices: (readonly [string | number, string])[]) {
  if (isWallpaper) {
    const text = choices.find(([key]) => key === value)?.[1] ?? "自定义";
    return `<button type="button" ${attributes} class="quality-cycle" aria-label="${label}" title="点击切换${label}" value="${value}" data-quality-choices="${escapeHtml(JSON.stringify(choices))}"><span data-quality-label>${text}</span><span aria-hidden="true">↻</span></button>`;
  }
  return `<select ${attributes} aria-label="${label}">${choices.map(([key, text]) => `<option value="${key}" ${key === value ? "selected" : ""}>${text}</option>`).join("")}${value === "custom" ? '<option value="custom" disabled selected>自定义</option>' : ""}</select>`;
}

if (isWallpaper) document.addEventListener("click", event => {
  const button = (event.target as Element).closest<HTMLButtonElement>("[data-quality-choices]");
  if (!button || button.disabled) return;
  const choices = JSON.parse(button.dataset.qualityChoices!) as [string | number, string][];
  const index = choices.findIndex(([value]) => String(value) === button.value);
  const [value, label] = choices[(index + 1) % choices.length];
  button.value = String(value);
  button.querySelector("[data-quality-label]")!.textContent = label;
  button.dispatchEvent(new Event("change", { bubbles: true }));
});

export function qualityMarkup(quality: RenderQuality) {
  const preset = matchingPreset(quality);
  return `<section class="quality-settings" aria-label="画质设置">
    <div class="quality-heading"><h3>RENDER QUALITY <span>渲染画质</span></h3>${choiceControl('id="quality-preset"', "画质预设", preset, (Object.keys(presetLabels) as QualityPreset[]).map(key => [key, presetLabels[key]]))}</div>
    <p class="quality-summary" id="quality-summary" aria-live="polite"></p>
    <p class="quality-note">${isWallpaper ? "即时生效，仅限当前运行；长期设置请在 Wallpaper Engine 中调整。" : "即时生效并自动保存。"}</p>
  </section>`;
}

export function syncQualityUI(quality: RenderQuality) {
  const preset = document.querySelector<HTMLSelectElement | HTMLButtonElement>("#quality-preset");
  if (!preset) return;
  const value = matchingPreset(quality);
  if (preset instanceof HTMLSelectElement) {
    let custom = preset.querySelector<HTMLOptionElement>('option[value="custom"]');
    if (value === "custom" && !custom) {
      custom = new Option("自定义", "custom");
      custom.disabled = true;
      preset.add(custom);
    } else if (value !== "custom") {
      custom?.remove();
    }
  }
  preset.value = value;
  document
    .querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLButtonElement>("[data-quality]")
    .forEach((control) => {
      const key = control.dataset.quality as keyof RenderQuality;
      control.value = String(quality[key]);
      control.disabled = key === "aoResolution" && quality.aoSamples === 0;
    });
  document.querySelectorAll<HTMLButtonElement>("[data-quality-choices]").forEach(button => {
    const choices = JSON.parse(button.dataset.qualityChoices!) as [string | number, string][];
    button.querySelector("[data-quality-label]")!.textContent = choices.find(([value]) => String(value) === button.value)?.[1] ?? "自定义";
  });
  document
    .querySelectorAll<HTMLOutputElement>("[data-quality-output]")
    .forEach((output) => {
      output.value = `${quality[output.dataset.qualityOutput as keyof RenderQuality]}%`;
    });
}
