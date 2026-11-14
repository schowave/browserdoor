// Copy buttons: shown only when the Clipboard API is there; without JavaScript the command stays selectable.
for (const button of document.querySelectorAll("button[data-copy]")) {
  if (!navigator.clipboard) continue;
  const source = document.getElementById(button.dataset.copy);
  button.hidden = false;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(source.textContent.trim());
      button.textContent = "Copied";
    } catch {
      button.textContent = "Select and copy";
    }
    setTimeout(() => (button.textContent = "Copy"), 2000);
  });
}
