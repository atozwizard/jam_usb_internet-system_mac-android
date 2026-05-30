# Stage 0: Current MVP Stabilization

Goal: preserve the working Chrome-only path while preparing system mode.

Deliverables:

- `browser --mobile-only` remains default double-click behavior.
- `proxy-stop` is safe to run repeatedly.
- RNDIS/native `connect` remains explicit and non-default.

Acceptance tests:

```zsh
./jam-usb-internet doctor
./jam-usb-internet browser --mobile-only
./jam-usb-internet proxy-stop
```

Known limitation:

- This stage does not provide Mac-wide internet.

