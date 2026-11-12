# The container tests' image (scripts/dev/container-test.sh): the packages
# the daemon and the compositors need (hyprland for the nested Hyprland check,
# xdg-desktop-portal for the niri portal line), every package install.sh would
# ask for with the three compositors installed (the uninstall round trip runs it with sudo refused), a
# keyring, a user to run as.
FROM archlinux:latest
RUN pacman -Syu --noconfirm --needed go gcc git python lua qt6-declarative quickshell sway niri hyprland mesa dbus xdg-desktop-portal glib2 gsettings-desktop-schemas xcursor-themes fcitx5 \
    accountsservice ddcutil greetd greetd-agreety kimageformats libavif libjxl libpulse libqalculate libsecret networkmanager \
    nm-connection-editor pacman-contrib power-profiles-daemon qt6-imageformats satty udisks2 wf-recorder \
    xdg-desktop-portal-gtk xdg-desktop-portal-wlr xorg-xwayland gnome-keyring \
    wlsunset xdg-desktop-portal-gnome xdg-desktop-portal-hyprland xwayland-satellite grim \
    && pacman -Scc --noconfirm
# sway ships with file capabilities a container without them can't exec
RUN setcap -r /usr/bin/sway
RUN useradd -m tester && install -d -o tester -g tester /home/tester/.cache
ENV AXIOM_CONTAINER=1
# the cache volume is the only writable place that outlives a run
ENV GOMODCACHE=/home/tester/.cache/go-mod
