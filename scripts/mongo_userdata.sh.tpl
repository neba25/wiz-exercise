#!/bin/bash
set -euxo pipefail

# ---------------------------------------------------------------------------
# Installs an INTENTIONALLY OUTDATED MongoDB (1+ year old major version).
# Check https://www.mongodb.com/docs/manual/release-notes/ for current
# release and pick a version from 1+ years back — 4.4 or 5.0 lines are good
# candidates depending on when you run this. Adjust the repo line below to
# match the version you pick.
# ---------------------------------------------------------------------------

apt-get update -y
apt-get install -y gnupg curl awscli

curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg] http://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-4.4.list

apt-get update -y
apt-get install -y mongodb-org=4.4.29 mongodb-org-server=4.4.29 mongodb-org-shell=4.4.29 mongodb-org-mongos=4.4.29 mongodb-org-tools=4.4.29 || \
  apt-get install -y mongodb-org

# Bind to all interfaces so it's reachable from the k8s private subnet
# (network access is restricted at the Security Group layer, not here)
sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl enable mongod
systemctl start mongod
sleep 5

# Create admin + app users, then enable auth (INTENTIONAL: auth required,
# but network-layer restriction to k8s CIDR only — done via the SG in
# mongo_vm.tf)
mongo <<EOF
use admin
db.createUser({
  user: "root",
  pwd: "${mongo_admin_password}",
  roles: [ { role: "root", db: "admin" } ]
})
use todoapp
db.createUser({
  user: "appuser",
  pwd: "${mongo_admin_password}",
  roles: [ { role: "readWrite", db: "todoapp" } ]
})
EOF

sed -i '/^#security:/a security:\n  authorization: enabled' /etc/mongod.conf
systemctl restart mongod

# ---------------------------------------------------------------------------
# Daily backup -> S3 (public bucket is intentional, configured in Terraform)
# ---------------------------------------------------------------------------
cat > /usr/local/bin/mongo_backup.sh <<'BACKUP'
#!/bin/bash
set -euxo pipefail
TS=$(date +%Y%m%d-%H%M%S)
OUTDIR="/tmp/mongo-backup-$TS"
mkdir -p "$OUTDIR"
mongodump --username root --password '${mongo_admin_password}' --authenticationDatabase admin --out "$OUTDIR"
tar -czf "$OUTDIR.tar.gz" -C "$OUTDIR" .
aws s3 cp "$OUTDIR.tar.gz" "s3://${backup_bucket}/backups/mongo-backup-$TS.tar.gz" --region ${aws_region}
rm -rf "$OUTDIR" "$OUTDIR.tar.gz"
BACKUP
chmod +x /usr/local/bin/mongo_backup.sh

# Run daily at 03:00 UTC
echo "0 3 * * * root /usr/local/bin/mongo_backup.sh >> /var/log/mongo_backup.log 2>&1" > /etc/cron.d/mongo-backup
chmod 644 /etc/cron.d/mongo-backup

# Run one backup immediately so there's evidence in the bucket for the demo
/usr/local/bin/mongo_backup.sh || true
