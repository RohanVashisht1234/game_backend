FROM archlinux:latest

RUN pacman -Syu --noconfirm && \
    pacman -S --noconfirm zig && \
    pacman -Scc --noconfirm

WORKDIR /app

COPY . .

RUN zig build -Doptimize=ReleaseFast

EXPOSE 8080

CMD ./zig-out/bin/game_backend