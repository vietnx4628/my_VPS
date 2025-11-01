{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.docker
    pkgs.cloudflared
    pkgs.socat
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.sudo
    pkgs.apt
    pkgs.unzip
  ];

  services.docker.enable = true;

  idx.workspace.onStart = {
    novnc = ''
      set -e

      # Cleanup 1 lần duy nhất
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/*
        find /home/user -mindepth 1 -maxdepth 1 ! -name 'idx-ubuntu22-gui' ! -name '.*' -exec rm -rf {} +
        touch /home/user/.cleanup_done
      fi


      ###########################################
      # ✅ Khởi tạo container + auto-restart 24/7
      ###########################################
      if ! docker ps -a --format '{{.Names}}' | grep -qx 'ubuntu-novnc'; then
        docker run --name ubuntu-novnc \
          --restart=always \
          --shm-size 1g -d \
          --cap-add=SYS_ADMIN \
          -p 8080:10000 \
          -e VNC_PASSWD=12345678 \
          -e PORT=10000 \
          -e AUDIO_PORT=1699 \
          -e WEBSOCKIFY_PORT=6900 \
          -e VNC_PORT=5900 \
          -e SCREEN_WIDTH=1024 \
          -e SCREEN_HEIGHT=768 \
          -e SCREEN_DEPTH=24 \
          thuonghai2711/ubuntu-novnc-pulseaudio:22.04
      else
        docker start ubuntu-novnc || true
      fi


      ###########################################
      # ✅ Cài Chrome nếu chưa có
      ###########################################
      docker exec ubuntu-novnc bash -lc '
        if ! command -v google-chrome >/dev/null 2>&1; then
          sudo apt update
          sudo apt remove -y firefox || true
          sudo apt install -y wget
          sudo wget -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
          sudo apt install -y /tmp/chrome.deb
          sudo rm -f /tmp/chrome.deb
        fi
      '


      ####################################################
      # ✅ Cloudflared – Auto restart + Auto reconnect 24/7
      ####################################################
      echo "[INFO] Starting cloudflared tunnel..."
      pkill cloudflared || true
      
      start_tunnel() {
        nohup cloudflared tunnel --no-autoupdate --url http://localhost:8080 \
          > /tmp/cloudflared.log 2>&1 &
      }

      start_tunnel
      sleep 10

      URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
      echo "========================================="
      echo " ✅ Cloudflared URL:"
      echo "     $URL"
      echo "========================================="


      ########################################################
      # ✅ Loop nền: tự kiểm tra Cloudflared mỗi 10 phút
      ########################################################
      (
        while true; do
          if ! pgrep cloudflared >/dev/null; then
            echo "[WARN] Cloudflared died — restarting"
            start_tunnel
          fi

          # Nếu tunnel đổi URL → thông báo mới
          NEW=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
          if [ "$NEW" != "$URL" ]; then
            URL="$NEW"
            echo "[INFO] Tunnel refreshed: $URL"
          fi

          sleep 600   # mỗi 10 phút
        done
      ) &


      ####################################################
      # ✅ Keep-alive loop – GIỮ IDx SỐNG > 72H (vô hạn)
      ####################################################
      (
        while true; do
          echo "[ALIVE] Workspace still running at $(date)"
          sleep 300    # 5 phút gửi tín hiệu 1 lần
        done
      ) &
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      novnc = {
        manager = "web";
        command = [
          "bash" "-lc"
          "socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:127.0.0.1:8080"
        ];
      };
    };
  };
}
