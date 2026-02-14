FROM nginx:alpine

# Simple test page for mini-idp build pipeline verification
RUN echo '<!DOCTYPE html><html><body><h1>mini-idp build pipeline works!</h1><p>Custom image deployed successfully.</p></body></html>' > /usr/share/nginx/html/index.html

EXPOSE 80
