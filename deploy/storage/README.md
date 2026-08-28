# Object storage

Downloads are served straight from Hetzner object storage (bucket `yznts`,
endpoint `nbg1.your-objectstorage.com`). Nothing runs to serve them: no
container, no proxy, no domain of ours in the path.

The bucket is shared with Immich and gamestash, so public read is scoped to
the `releases/` prefix by `bucket-policy.json`. Everything else answers only
to credentials — Immich reaches its files through the rclone mount at
`/mnt/s3`, gamestash signs 15-minute urls.

Applying it (from nue-4, which holds the credentials):

```sh
KEY=$(rclone config show hetzner | awk -F'= ' '/access_key_id/{print $2}')
SEC=$(rclone config show hetzner | awk -F'= ' '/secret_access_key/{print $2}')
docker run --rm -e AWS_ACCESS_KEY_ID="$KEY" -e AWS_SECRET_ACCESS_KEY="$SEC" \
  -e AWS_DEFAULT_REGION=nbg1 -v ~/Applications/Static:/work -w /work amazon/aws-cli \
  s3api put-bucket-policy --bucket yznts --policy file:///work/bucket-policy.json \
  --endpoint-url https://nbg1.your-objectstorage.com
```

Checking it, from anywhere:

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://yznts.nbg1.your-objectstorage.com/releases/babel/<version>/<file>   # 200
curl -s -o /dev/null -w '%{http_code}\n' https://yznts.nbg1.your-objectstorage.com/Immich/backups/.immich           # 403
```

This replaced a policy that granted public read on `yznts/*`, which had left
every Immich backup and gamestash object readable by anyone with the key
name. The previous version is kept on the box as
`~/Applications/Static/bucket-policy.previous.json`.
