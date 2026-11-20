# Hệ Thống Giám Sát & Thu Thập Log Tập Trung (Monitoring Stack)

Dự án triển khai hệ thống giám sát hạ tầng và thu thập log tập trung bằng Docker Compose trên Ubuntu Server, kết hợp **Zabbix**, **Grafana**, **Loki** và **Grafana Alloy**.

---

## 1. Thành phần hệ thống

| Service | Image | Chức năng |
| :--- | :--- | :--- |
| `loki` | `grafana/loki:latest` | Lưu trữ và truy vấn log tập trung (lưu giữ 336 giờ / 14 ngày). |
| `alloy` | `grafana/alloy:latest` | Thu thập log hệ thống Linux (`/var/log`), log Docker container và Syslog từ thiết bị mạng. |
| `grafana` | `grafana/grafana:latest` | Giao diện trực quan hóa dữ liệu, dashboard hợp nhất (Metrics & Logs). |
| `zabbix-db` | `postgres:16-alpine` | Cơ sở dữ liệu PostgreSQL cho Zabbix. |
| `zabbix-server` | `zabbix/zabbix-server-pgsql:alpine-7.0-latest` | Zabbix Server thu thập metrics từ các host/thiết bị mạng. |
| `zabbix-web` | `zabbix/zabbix-web-nginx-pgsql:alpine-7.0-latest` | Giao diện web quản trị Zabbix (múi giờ `Asia/Ho_Chi_Minh`). |

---

## 2. Cấu trúc thư mục

```text
monitoring/
├── alloy/
│   └── config.alloy        # Cấu hình thu thập log cho Grafana Alloy
├── loki/
│   └── loki-config.yaml    # Cấu hình lưu trữ & retention cho Loki
├── docker-compose.yml      # Khai báo toàn bộ các container, volume và network
├── run-docker.sh       # Script tự động cài Docker và khởi chạy stack trên Ubuntu Server
└── README.md
```

---

## 3. Yêu cầu hệ thống

- **Hệ điều hành:** Ubuntu Server (hỗ trợ chạy script cài đặt tự động với quyền `root` hoặc user có `sudo`).
- **Kết nối mạng:** Có Internet để tải gói cài đặt Docker và pull Docker images.
- **Tài nguyên khuyến nghị:** Tối thiểu 2 vCPU, 4 GB RAM, 20 GB ổ cứng trống.

---

## 4. Hướng dẫn cài đặt nhanh

Script `run-docker.sh` sẽ tự động kiểm tra lỗi theo từng bước (dừng ngay nếu có bước thất bại):
1. Kiểm tra môi trường Ubuntu Server, quyền `sudo` và sự tồn tại của `docker-compose.yml`.
2. Gỡ bỏ các gói Docker cũ/xung đột (nếu có).
3. Cập nhật APT và cài đặt `ca-certificates`, `curl`.
4. Thêm Docker GPG key chính thức.
5. Thêm Docker APT repository.
6. Cài đặt Docker Engine và Docker Compose plugin.
7. Kích hoạt dịch vụ `docker`, kiểm tra phiên bản và thêm user hiện tại vào nhóm `docker`.
8. Kiểm tra cú pháp `docker-compose.yml` và khởi chạy toàn bộ container (`docker compose up -d`).

### Các bước thực hiện

```bash
chmod +x run-docker.sh
./run-docker.sh
```

> **Lưu ý:** Nếu bạn chạy script bằng user thường (không phải `root`), hãy đăng xuất và đăng nhập lại (hoặc chạy `newgrp docker`) sau khi cài xong để sử dụng lệnh `docker` mà không cần `sudo`.

---

## 5. Thông tin truy cập & Cổng kết nối (Ports)

### Giao diện Web

| Dịch vụ | URL truy cập | Tài khoản mặc định |
| :--- | :--- | :--- |
| **Grafana** | `http://<IP-SERVER>:3000` | User: `admin` / Pass: `Home!23$` |
| **Zabbix Web** | `http://<IP-SERVER>:8080` | User: `Admin` / Pass: `zabbix` |

> **Khuyến nghị bảo mật:** Hãy đổi mật khẩu mặc định của Grafana (trong `docker-compose.yml` hoặc trên giao diện web) và Zabbix ngay sau lần đăng nhập đầu tiên.

### Các cổng dịch vụ khác

| Cổng | Giao thức | Dịch vụ | Mục đích |
| :--- | :--- | :--- | :--- |
| `3100` | TCP | Loki | API nhận và truy vấn log |
| `514` | TCP / UDP | Grafana Alloy | Nhận Syslog từ thiết bị mạng Cisco (`syslog_format = "raw"`) |
| `1514` | TCP / UDP | Grafana Alloy | Nhận Syslog từ thiết bị mạng FortiGate |
| `10051` | TCP | Zabbix Server | Nhận dữ liệu từ Zabbix Agent / Proxy |

---

## 6. Chi tiết cấu hình Log (Alloy & Loki)

- **Log hệ thống Linux:** Alloy đọc các file `/var/log/*.log` trên host (gắn nhãn `job="varlogs"`, `host="main-server"`).
- **Log Docker Containers:** Alloy tự động phát hiện qua `/var/run/docker.sock` và gắn nhãn `container_name`.
- **Syslog thiết bị mạng:**
  - Port `514` (TCP/UDP): Gắn nhãn `source="cisco"`.
  - Port `1514` (TCP/UDP): Gắn nhãn `source="fortigate"`, tự động trích xuất thêm `devname` (làm `host`) và `level` từ nội dung log.
  - Có thể bỏ comment phần map IP thủ công trong `alloy/config.alloy` nếu muốn ánh xạ IP thiết bị mạng sang tên Host trên Zabbix.
- **Thời gian lưu trữ (Loki):** Cấu hình trong `loki/loki-config.yaml` với `retention_period: 336h` (14 ngày).

---

## 7. Các lệnh quản trị thường dùng

Chạy các lệnh sau trong thư mục `monitoring/`:

```bash
# Xem trạng thái các container
docker compose ps

# Xem log của toàn bộ stack hoặc từng service (ví dụ: alloy, loki)
docker compose logs -f
docker compose logs -f alloy

# Khởi động lại toàn bộ hoặc một service sau khi sửa cấu hình
docker compose restart
docker compose restart alloy

# Cập nhật image mới nhất và khởi chạy lại
docker compose pull
docker compose up -d

# Dừng các container (vẫn giữ lại dữ liệu trong volumes)
docker compose down
```
