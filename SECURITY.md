# Security

## Scope

ChipLab is a local-first demo and reference implementation. It does not connect to an
exchange, place orders, or store credentials. The local API binds to `127.0.0.1` by
default and has no authentication; do not expose it to an untrusted network without a
reverse proxy and access control.

## Reporting

Email `timfromhcs@gmail.com` with a description and reproduction. Do not open a public
issue for a vulnerability that could affect a deployed instance.

## Practices

- No secrets in the repository or in generated reports.
- The Vercel API is stateless; per-user data stays in the browser.
- WASM runs in a Worker, but it is not a security boundary against a malicious module;
  only load the bundled `chiplab_core.wasm`.
- `--boost` changes Windows process priority/affinity only when explicitly requested.
- Dependencies: Node built-ins for the server, Rust `wgpu`/`pollster`/`bytemuck` for the
  native runner, Python stdlib for the model. Review `npm audit` and `cargo audit` before
  publishing.
