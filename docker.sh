/usr/bin/docker run --name phone_db \
      --rm -ti --network=host \
      -e DATABASE_URL="$DATABASE_URL" \
      -e GUARDIAN_SECRET="$GUARDIAN_SECRET" \
      -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
      -e SIGNING_SALT=="$SIGNING_SALT" \
      -p 4001:4000 \
      brianmay/scrooge "$@"
