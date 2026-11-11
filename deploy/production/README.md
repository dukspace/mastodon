# duk.space 운영 배포 준비 및 최초 전환

이 문서는 **배포 준비용**이다. 저장소 변경이나 CI 검증은 운영에 배포하지 않는다.
아래 서버 명령은 별도의 운영 배포 시점에 실행한다. 최초 전환을 자동으로 실행하는
스크립트나 Production 배포 워크플로는 제공하지 않는다.

## 범위와 유지할 구성

2026-10-28 읽기 전용 조사 기준:

- Ubuntu 24.04 ARM64, 공식 Mastodon 4.7.3 (`8ff11c2bb7b9f0714e947b10fa3629c6542c7121`).
- 기존 설치 `/home/mastodon/live`와 그 로컬 수정·환경 파일은 복구용으로 보존한다.
- 앱만 이 Compose의 Web / Streaming / Sidekiq로 전환한다.
- 기존 RDS PostgreSQL 15.17, 별도 Redis 8.0.3, Elasticsearch 7.17.29, S3를 사용한다.
- Nginx의 HTTPS, 인증서 갱신, Web `127.0.0.1:3000`, Streaming `127.0.0.1:4000`을 유지한다.
- `/inbox`, `/users/.../inbox` → `@budae` → `127.0.0.1:7000` 경로와
  `budae-jjigae-budae-1` 컨테이너를 유지한다. 해당 컨테이너는 host 네트워크를 사용한다.
- 호스트의 로컬 PostgreSQL·Redis는 별도로 실행 중이다. 용도가 확정되기 전에는
  중지·삭제하지 않는다. `docker system prune`, `compose down -v`도 사용하지 않는다.

Compose 프로젝트 이름은 `mastodon-production`이며 DB, Redis, 검색, Nginx,
budae 서비스를 포함하지 않는다. 루트 `docker-compose.yml`과 합쳐 실행하지 않는다.
새 Compose는 bridge 네트워크에서 외부 서비스에 접속하고 앱 포트만 loopback에 공개한다.
S3 전용 구성이라 기존 `public/system` 마운트는 없다. 로컬 미디어가 있는 경우 먼저 재설계한다.

## 배포 시작 조건

1. 이 변경을 포함한 **4.7.3 기반 커밋**을 Staging에서 검증한다.
   운영은 이미 4.7.3이므로 이전 4.7.2 이미지로 내려가지 않는다.
   이동하는 `staging` 태그 대신 `sha-<전체 40자리 SHA>`를 선택하고 두 이미지의
   digest와 ARM64 지원을 기록한다. 재빌드하지 않고 검증한 이미지를 승격한다.
   `duk-v4.7.3-1` 같은 Git 릴리스 태그는 선택한 커밋의 표시이며 태그 생성만으로
   배포하지 않는다. `production` 브랜치의 최신 커밋을 배포 대상으로 사용하지 않는다.
   브랜치 역할과 전환 순서는 [배포 흐름](../README.md)을 따른다.
2. 조사 당시 메모리는 총 1.8GiB / 가용 약 85MiB, 디스크는 95% 사용 / 1.6GB 여유였다.
   이미지 압축 해제, 정적 파일 두 버전, 로그, 복구 자료를 보관할 공간과 런타임 메모리를
   먼저 확보한다. 사전 검증용 앱을 기존 앱과 병행 실행하지 않는다.
3. RDS 복원본 + 독립 Redis에서 리허설한다. 운영 도메인 데이터의 외부 발송을 차단하고
   SMTP, 연합, 웹훅, 운영 S3 쓰기·삭제를 격리한다. 운영 Redis 큐를 리허설에 연결하지 않는다.
   마이그레이션 시간, CA 검증, 검색, S3 읽기/쓰기, 5,000자, 반응 기능을 검증한다.
4. 커스텀 마이그레이션은 `20260819090000_create_status_reactions` 한 개다.
   알림 테이블은 조사 시 추정 54,076행 / 29MB였지만 실제 소요 시간은 리허설로 측정한다.
   새 테이블 두 개와 알림 컬럼·인덱스·외래 키를 추가한다. 전체 트랜잭션이 아니므로
   중간 실패 시 부분 생성된 객체를 확인한다. 무조건 재실행하거나 `db:rollback`하지 않는다.
5. RDS 복원, Redis 큐 보존, 기존 앱 재기동 절차를 검증하고 두 시간 점검 중 복구 시간을
   따로 남긴다. DB 복원 소요 시간을 모르면 두 시간 내 복구 가능하다고 가정하지 않는다.

## 환경 파일과 인증서 준비

운영 EC2에 코드의 별도 checkout을 `/opt/mastodon-production`으로 준비한다.
기존 `/home/mastodon/live`에 `git reset`, `checkout`, `pull`을 실행하지 않는다.
아래는 해당 checkout을 준비한 뒤의 예시다. 모든 셸 예시는 Bash 기준이다.

```bash
sudo install -d -o mastodon -g mastodon -m 0700 /etc/mastodon-production
sudo install -m 0644 /home/mastodon/live/rds-seoul.pem /etc/mastodon-production/rds-ca.pem

# 기존 설치와 같은 dotenv 파서로 해석한 뒤 Compose raw 형식으로 저장한다.
# 파일은 새로 만들 때만 기록되며 값은 터미널에 출력하지 않는다.
sudo -u mastodon bash -c 'cd /home/mastodon/live && /home/mastodon/.rbenv/shims/bundle exec ruby /opt/mastodon-production/deploy/production/prepare_env.rb /home/mastodon/live/.env.production /etc/mastodon-production/runtime.env'
sudo chown root:root /etc/mastodon-production/runtime.env
sudo chmod 0600 /etc/mastodon-production/runtime.env

sudo install -m 0600 /opt/mastodon-production/deploy/production/deploy.env.example /etc/mastodon-production/deploy.env
sudoedit /etc/mastodon-production/deploy.env
```

`deploy.env`는 Compose 변수 전용이며 앱 시크릿을 넣지 않는다. 이미지 태그의 placeholder를
검증한 SHA로 교체한다. Compose 2.30 이상이 필요하며 조사한 서버는 2.38.2다.
`runtime.env`는 `format: raw`로 읽으므로 값에 따옴표나 역슬래시를 추가하지 않는다.
수동으로 기존 dotenv 파일을 복사하면 따옴표가 비밀번호에 포함될 수 있으므로 변환기를 사용한다.

운영의 `LOCAL_DOMAIN`, `WEB_DOMAIN`(설정된 경우), 모든 기존 시크릿·암호화 키,
DB·Redis·ES·S3·SMTP 설정을 유지한다. 키를 재생성하지 않는다.
기존 환경변수 외에 systemd drop-in이나 별도 설정이 추가되었는지도 배포 당일 확인한다.
`DATABASE_URL`/`REPLICA_DATABASE_URL`이 있으면 변환기는 중단한다. URL이 DB 필드와 TLS 설정을
덮어쓸 수 있으므로 개별 DB 변수로 정리한 사본을 만들고 연결을 다시 검증한다.

Compose는 세 서비스에 `DB_SSLMODE=verify-full`과
`PGSSLROOTCERT=/etc/mastodon/rds-ca.pem`을 지정한다. Rails는 libpq의 CA 설정을 사용하고,
Streaming도 같은 파일을 읽는다. 운영의 인증서 직접 읽기 패치를 대체하며 인증서 검증을 끄지 않는다.
RDS 실제 DNS endpoint를 사용하고 CA 파일의 유효성·읽기 권한을 확인한다. 기존 CA를 교체해야 한다면
[AWS RDS 인증서 문서](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)의
서울 리전 bundle을 사용한다. CA는 공개 인증서이며 개인 키나 DB 비밀번호가 아니다.

## 이미지와 정적 파일 사전 준비

이후 같은 Bash 세션에서 아래 함수를 사용한다. Compose 명령은 이 프로젝트만 대상으로 한다.

```bash
prod() {
  sudo docker compose --env-file /etc/mastodon-production/deploy.env \
    -f /opt/mastodon-production/deploy/production/compose.yml "$@"
}

DEPLOY_SHA=REPLACE_WITH_VERIFIED_FULL_COMMIT_SHA
[[ "$DEPLOY_SHA" =~ ^[0-9a-f]{40}$ ]] || { echo 'Set DEPLOY_SHA'; exit 1; }
IMAGE="ghcr.io/dukspace/mastodon:sha-$DEPLOY_SHA"
STATIC_RELEASE="/var/www/mastodon-production/releases/$DEPLOY_SHA"

prod config --quiet
prod config --images
# 위 출력의 두 이미지 태그가 DEPLOY_SHA와 일치하는지 확인한다.
prod pull web streaming sidekiq
sudo docker image inspect "$IMAGE" --format '{{json .RepoDigests}}'
sudo docker image inspect "ghcr.io/dukspace/mastodon-streaming:sha-$DEPLOY_SHA" --format '{{json .RepoDigests}}'
# 두 이미지 모두 Architecture=arm64, revision=DEPLOY_SHA인지 확인한다.
sudo docker image inspect "$IMAGE" "ghcr.io/dukspace/mastodon-streaming:sha-$DEPLOY_SHA" \
  --format '{{.Architecture}} {{index .Config.Labels "org.opencontainers.image.revision"}}'

sudo install -d -m 0755 /var/www/mastodon-production/releases
sudo bash /opt/mastodon-production/deploy/production/prepare-assets.sh \
  "$IMAGE" "$DEPLOY_SHA" "$STATIC_RELEASE"
```

GHCR가 비공개이면 배포용 계정의 `read:packages` 권한으로 **실제로 pull을 실행하는 계정**에
먼저 인증한다. 토큰을 명령행 인자로 넣지 않는다. `sudo docker`는 root의 인증 설정을 사용한다.
`prod config` 전체 출력은 비밀 값이 노출될 수 있으므로 `--quiet` / `--images`만 사용한다.

`prepare-assets.sh`는 이미지의 `SOURCE_COMMIT`을 확인하고 실행하지 않는 임시 컨테이너에서
`public`을 추출한다. 앱을 시작하거나 DB에 연결하지 않는다. 운영의 기존 정적 파일은 덮어쓰지 않는다.
새 release 디렉터리는 Nginx가 읽을 수 있고 상위 디렉터리도 통과 가능해야 한다.
`public` 전체를 Web 컨테이너 위에 마운트하지 않는다.

이전 브라우저가 요청할 수 있는 정적 파일도 남긴다. 새 파일은 덮어쓰지 않는다.

```bash
sudo cp -an /home/mastodon/live/public/assets/. "$STATIC_RELEASE/assets/"
sudo cp -an /home/mastodon/live/public/packs/. "$STATIC_RELEASE/packs/"
```

## Nginx 준비: 기존 파일에 최소 변경

기존 `/etc/nginx/sites-enabled/mastodon`의 실제 대상 파일을 확인하고 원본을 백업한다.
인증서·upstream·WebSocket 헤더·`@budae`·inbox location·ACME 설정은 그대로 둔다.
사이트 파일 전체를 저장소의 예제 `dist/nginx.conf`로 교체하지 않는다.

1. 기존 HTTPS `server` 블록에 아래 include를 추가한다.
2. 처음에는 기존 `root /home/mastodon/live/public;`을 유지한다.
3. `nginx -t` 성공 후 reload한다. maintenance 파일이 없으면 기존 서비스가 계속된다.

```nginx
include /etc/nginx/snippets/mastodon-production-maintenance.conf;
```

```bash
sudo install -m 0644 /opt/mastodon-production/deploy/production/nginx-maintenance.conf \
  /etc/nginx/snippets/mastodon-production-maintenance.conf
# 사이트 파일 백업 및 include 추가 후에만 실행
sudo nginx -t && sudo systemctl reload nginx
```

이 guard는 maintenance 파일이 있을 때 정적 파일, Web, Streaming, budae inbox까지 503으로
막는다. 기존 WebSocket 연결과 이미 처리 중인 요청까지 종료하지는 않는다.
전환 시 기존 앱 종료와 budae 진행 중 요청의 drain 확인을 함께 수행한다.

## 점검 시간: 최초 전환

1. 유지보수 진입 후 외부의 `/`, `/inbox`, 사용자 inbox, `/api/v1/streaming/health`가
   503인지 확인한다. inbox 확인에는 GET만 사용한다. 테스트용 연합 POST를 보내지 않는다.

   ```bash
   sudo touch /var/www/mastodon-production/maintenance
   curl -sS -o /dev/null -w '%{http_code}\n' https://duk.space/
   curl -sS -o /dev/null -w '%{http_code}\n' https://duk.space/inbox
   ```

2. 기존 Sidekiq에 TSTP를 보내 새 작업 수신을 멈추고 처리 중 작업이 끝나는지 확인한다.
   systemd의 기존 종료 제한은 짧을 수 있으므로 busy 작업이 남은 상태에서 강제 종료하지 않는다.
   Web·Streaming·다른 cron/tootctl 작성자와 budae의 진행 중 요청까지 정리해 쓰기를 멈춘다.
   budae가 큐를 재처리하는 구성이라면 그 생산 경로를 먼저 확인해 drain을 보장한다.
   용도가 불명확한 로컬 Redis/PostgreSQL을 중지하는 방식으로 해결하지 않는다.

   ```bash
   sudo systemctl kill --kill-whom=main --signal=TSTP mastodon-sidekiq.service
   # busy 작업이 0이고 다른 작성자가 없는지 확인한 뒤 진행
   sudo systemctl stop mastodon-web.service mastodon-streaming.service mastodon-streaming@4000.service mastodon-sidekiq.service
   sudo ss -lntp '( sport = :3000 or sport = :4000 )'
   # 출력에 listener가 없어야 한다. budae의 7000 포트는 유지한다.
   ```

3. 쓰기가 멈춘 시점의 RDS snapshot과 Redis 상태/큐 백업을 확보하고 완료 상태를 확인한다.
   기존 앱 코드·로컬 패치·환경 파일·CA·systemd·Nginx 백업도 접근 제한된 위치에 둔다.
   복원 시 RDS의 새 endpoint 반영, Redis 큐와 DB 시점 정합성, 소요 시간을 확인한다.

4. 새 이미지에서 연결과 pending migration을 확인한다. `run`은 서비스 포트를 공개하지 않는다.
   아래 Rails 명령은 앱을 부팅하므로 사전 용량 확보와 기존 앱 중지 후 실행한다.

   ```bash
   prod run --rm --no-deps web bundle exec rails db:migrate:status
   prod run --rm --no-deps web bundle exec rails runner 'abort "Expected 5000" unless StatusLengthValidator::MAX_CHARS == 5000; abort "TLS required" unless ActiveRecord::Base.connection.select_value("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()")'
   ```

   `down`은 검토한 반응 마이그레이션 한 개만 있어야 한다. 다른 항목이 있거나 연결에 실패하면 중단한다.
   `db:setup`, `db:reset`, 자동 초기화를 포함하는 `db:prepare`는 사용하지 않는다.

   ```bash
   prod run --rm --no-deps web bundle exec rails db:migrate
   prod run --rm --no-deps web bundle exec rails db:migrate:status
   ```

5. maintenance를 유지한 채 정적 파일 symlink를 선택하고 기존 HTTPS 블록의 `root`만
   `/var/www/mastodon-production/current`로 바꾼다. HTTP/ACME 블록의 root는 유지한다.
   `/sw.js`, `/assets/`, `/packs/` 등 기존 `try_files`가 새 root를 사용하는지 확인한다.

   ```bash
   sudo ln -s "$STATIC_RELEASE" /var/www/mastodon-production/current
   # 최초 전환용: current가 이미 존재하면 덮어쓰지 말고 기존 배포 상태부터 확인
   sudo nginx -t && sudo systemctl reload nginx
   prod up -d --wait --wait-timeout 180 web streaming
   curl -fsS http://127.0.0.1:3000/health
   curl -fsS http://127.0.0.1:4000/api/v1/streaming/health
   prod exec -T web bundle exec rails runner 'abort "Wrong release" unless Mastodon::Version.source_commit == ARGV.fetch(0)' "$DEPLOY_SHA"
   ```

   Streaming health는 프로세스 생존 확인일 뿐 DB 연결 검증을 대신하지 않는다.
   Streaming에서 실제 TLS DB 조회도 수행한다.

   ```bash
   prod exec -T streaming node --input-type=module -e 'import pg from "pg"; import { configFromEnv } from "./streaming/database.js"; const client = new pg.Client(configFromEnv(process.env, "production")); try { await client.connect(); const result = await client.query("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()"); if (!result.rows[0]?.ssl) throw new Error("TLS required"); console.log("Streaming DB TLS OK"); } finally { await client.end(); }'
   prod up -d --wait --wait-timeout 180 sidekiq
   prod ps
   ```

6. Sidekiq가 기존 큐를 소비하고 새 데이터를 만들기 시작하면 아래의 단순 앱 복귀 경계를 넘는다.
   큐 오류율·재시도·메모리를 확인하고, 기존 systemd 앱이 계속 정지 상태인지 확인한다.
   로컬 경로의 새 정적 파일이 Nginx 사용자에게 읽히는지 확인한 뒤 maintenance를 해제한다.

   ```bash
   sudo -u www-data test -r /var/www/mastodon-production/current/sw.js
   sudo rm /var/www/mastodon-production/maintenance
   ```

7. 공개 경로에서 로그인, 기존 미디어, 새 S3 업로드, 검색, Streaming WebSocket,
   5,000자 작성/5,001자 거절, 이모지 반응 및 알림을 확인한다.
   실제 계정으로 확인하는 쓰기 테스트는 운영 검증 작업으로 취급한다.
   브라우저에서 새 CSS·JS·서비스 워커가 200인지 확인하고, 실제 연합 송수신으로
   budae 경유 수신도 검증한다. `/health`만으로 성공 처리하지 않는다.
8. 안정화 후 기존 Web·Sidekiq·Streaming 및 실제 활성화된 template instance의
   systemd 부팅 자동 시작을 해제해 재부팅 시 포트 경쟁을 방지한다. 변경 전 enabled 상태를 기록한다.
   컨테이너의 재시작 정책과 Docker 부팅 설정도 확인한다. Nginx/budae/로컬 데이터 서비스는 유지한다.

## 실패 시 복구 경계

- **마이그레이션 전:** 새 앱이 실행되지 않았다면 기존 Nginx 백업/root를 복원하고
  `nginx -t` 후 reload한다. 기존 systemd 네 서비스를 시작해 health를 확인한 다음 maintenance를 해제한다.
  TSTP만 전송한 Sidekiq도 다시 시작해야 작업 수신이 재개된다.
- **마이그레이션 실패:** maintenance와 기존 앱 정지 상태를 유지한다. 부분 적용 여부와
  실패 원인을 조사한다. blind 재실행, migration 버전 수동 삽입, `db:rollback`은 하지 않는다.
  리허설에서 검증한 복구 또는 DB 복원을 선택한다.
- **마이그레이션 성공, 새 앱이 한 번도 데이터를 쓰지 않은 경우:** 추가 스키마를 남긴 채
  공식 4.7.3으로 돌아갈 수 있는지는 복원본에서 미리 검증해야 한다. 검증했다면
  `prod stop sidekiq web streaming` → 기존 Nginx 복원 → 기존 systemd 서비스 시작 순서로 복귀한다.
  단순 복귀를 위해 새 테이블을 삭제할 필요는 없다.
- **새 Web/Sidekiq가 실행되었거나 서비스가 공개된 경우:** 반응 알림·새 작업 큐를
  공식 코드가 처리한다고 보장할 수 없다. maintenance → 새 작성자 정지 → 데이터 보존 후
  수정 버전으로 전진 복구하거나, 합의한 복구 지점의 DB·큐를 함께 복원한다.
  DB만 과거로 돌리면 이후 게시물 손실·큐 불일치·이미 발송된 연합 활동과의 불일치가 생길 수 있다.

복귀 시 최초에 기록한 systemd enabled 상태도 복원한다. 백업과 이전 static release는
안정화 확인 전 삭제하지 않는다. 이 절차에는 자동 schema rollback이나 자동 DB 복원이 없다.

## 로컬/CI 검증

```bash
node --test streaming/database.test.mjs
bundle exec rspec spec/validators/status_length_validator_spec.rb spec/requests/api/v1/statuses_spec.rb spec/requests/api/v2/instance_spec.rb
bash -n deploy/production/prepare-assets.sh
ruby -c deploy/production/prepare_env.rb
```

Staging workflow는 위 기능 테스트와 Production Compose 구문 검증을 수행한다.
Production에 접속하거나 배포하는 job은 추가하지 않는다.
