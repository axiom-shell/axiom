# The container tests' image (scripts/dev/container-test.sh): the packages
# the daemon and the compositors need (hyprland for the nested Hyprland check,
# xdg-desktop-portal for the niri portal line), a user to run as.
FROM archlinux:latest
RUN pacman -Syu --noconfirm --needed go gcc git python lua qt6-declarative quickshell sway niri hyprland mesa dbus xdg-desktop-portal glib2 gsettings-desktop-schemas xcursor-themes fcitx5 \
    && pacman -Scc --noconfirm
# sway ships with file capabilities a container without them can't exec
RUN setcap -r /usr/bin/sway
RUN useradd -m tester && install -d -o tester -g tester /home/tester/.cache
ENV AXIOM_CONTAINER=1
# the cache volume is the only writable place that outlives a run
ENV GOMODCACHE=/home/tester/.cache/go-mod
