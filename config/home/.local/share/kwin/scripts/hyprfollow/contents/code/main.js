// Hyprland "movetoworkspace" for KWin: move the active window and follow it.
function moveAndFollow(index) {
    var w = workspace.activeWindow;
    var ds = workspace.desktops;
    if (!w || index < 0 || index >= ds.length) return;
    w.desktops = [ds[index]];
    workspace.currentDesktop = ds[index];
    workspace.activeWindow = w;
}
function currentIndex() {
    return workspace.desktops.indexOf(workspace.currentDesktop);
}
for (var i = 1; i <= 10; i++) {
    (function (n) {
        registerShortcut("HyprFollowToDesktop" + n,
            "Hyprfollow: Move window to desktop " + n + " and follow",
            "", function () { moveAndFollow(n - 1); });
    })(i);
}
registerShortcut("HyprFollowToNext", "Hyprfollow: Move window to next desktop and follow",
    "", function () { moveAndFollow(currentIndex() + 1); });
registerShortcut("HyprFollowToPrev", "Hyprfollow: Move window to previous desktop and follow",
    "", function () { moveAndFollow(currentIndex() - 1); });
