FROM nginx:alpine

# Create an entrypoint script that generates the HTML page at container start,
# which lets us verify environment variable injection from ECS task definition.
RUN printf '#!/bin/sh\n\
cat > /usr/share/nginx/html/index.html <<HTMLEOF\n\
<!DOCTYPE html>\n\
<html><body>\n\
<h1>mini-idp env var injection test</h1>\n\
<pre>\n\
IDP_APP_NAME = ${IDP_APP_NAME:-not set}\n\
IDP_ENV      = ${IDP_ENV:-not set}\n\
LOG_LEVEL    = ${LOG_LEVEL:-not set}\n\
</pre>\n\
</body></html>\n\
HTMLEOF\n\
exec nginx -g "daemon off;"\n' > /docker-entrypoint.d/99-env-page.sh && chmod +x /docker-entrypoint.d/99-env-page.sh

EXPOSE 80
