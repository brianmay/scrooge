/usr/bin/docker run --name phone_db \
      --rm -ti --network=host \
      -e DATABASE_URL="$DATABASE_URL" \
      -e GUARDIAN_SECRET="$GUARDIAN_SECRET" \
      -e SECRET_KEY_BASE="$SECRET_KEY_BASE" \
      -e SIGNING_SALT=="$SIGNING_SALT" \
      -e MQTT_HOST="$MQTT_HOST" \
      -e MQTT_PORT="$MQTT_PORT" \
      -e MQTT_CA_CERT_FILE="$MQTT_CA_CERT_FILE" \
      -e MQTT_USERNAME="$MQTT_USERNAME" \
      -e MQTT_PASSWORD="$MQTT_PASSWORD" \
      -v /etc/ssl/certs:/etc/ssl/certs \
      -v /usr/share/ca-certificates:/usr/share/ca-certificates \
      -p 4001:4000 \
      brianmay/scrooge "$@"
