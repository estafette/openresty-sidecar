# estafette/openresty-sidecar

Sidecar container based on Openresty to terminate ssl, auto-reload on certificate updates, output prometheus metrics and output Jaeger traces

# development

For running integration tests the container embeds a self-signed ssl certificate, which can be renewed by running the following commands:

```bash
cd ssl
openssl req -x509 -newkey rsa:4096 -keyout ssl.key -out ssl.pem -days 3650 -subj '/CN=localhost' -nodes
```