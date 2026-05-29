export function installDuskmoonConfirmDialogBridge() {
  document.addEventListener(
    "click",
    (event) => {
      const button = event.target.closest?.(
        "el-dm-dialog form[method='dialog'] el-dm-button"
      );

      if (!button || button.getAttribute("type") === "submit") return;

      const dialog = button.closest("el-dm-dialog");
      if (!dialog) return;

      event.preventDefault();
      event.stopPropagation();

      if (typeof dialog.close === "function") {
        dialog.close();
      } else {
        dialog.open = false;
      }
    },
    true
  );
}
