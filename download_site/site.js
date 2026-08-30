"use strict";

const repository = "cordonblue0622/CropCareAI";
const releaseApi = `https://api.github.com/repos/${repository}/releases/latest`;
const fallbackUrl = `https://github.com/${repository}/releases/latest`;
const downloadButton = document.querySelector("#downloadButton");
const releaseLabel = document.querySelector("#releaseLabel");

fetch(releaseApi, { headers: { Accept: "application/vnd.github+json" } })
  .then((response) => {
    if (!response.ok) throw new Error("No published release");
    return response.json();
  })
  .then((release) => {
    const apk = (release.assets || []).find((asset) => asset.name.toLowerCase().endsWith(".apk"));
    if (!apk) throw new Error("No APK in latest release");
    downloadButton.href = apk.browser_download_url;
    releaseLabel.textContent = `${release.name || release.tag_name} · ${(apk.size / 1024 / 1024).toFixed(1)} MB`;
  })
  .catch(() => {
    downloadButton.href = fallbackUrl;
    downloadButton.textContent = "View Android releases";
    releaseLabel.textContent = "The latest signed build appears here when published.";
  });
