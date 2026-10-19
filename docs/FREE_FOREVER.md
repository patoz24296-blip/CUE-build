# Free for everyone, permanently

This is a product requirement set by CUE's owner. CUE's official releases and every rehearsal feature must remain free for every user. Do not introduce subscriptions, premium tiers, purchase screens, paid voice packs, credits, usage quotas, trials, expiry timers, payment SDKs, account requirements or remote entitlement checks.

Speech recognition, voice generation, voice activity, script evaluation, meaning comparison, storage, recording and export run on the user's device. Do not add external AI APIs, API-key entry, hosted inference or a required companion server. The old optional local-server integration and its preferences have been removed. Legacy preference rows are ignored without deleting scripts or history.

Model downloads are explicit, resumable downloads of pinned free weights and supporting data. They are not metered inference requests. All currently selected recognition and voice models are downloaded without an API key or payment. Once the selected components are installed, rehearsal works offline. Missing optional components must explain the available local behavior; they must never route to a paid or cloud fallback.

Initial internet access is for component downloads. Do not upload scripts, dialogue, microphone audio or user recordings as part of rehearsal. Local exports remain deliberate user actions. Retain upstream license/attribution files with the models and dependencies.

Development and release work must respect the owner's zero-spend constraint. Do not purchase or enable paid build infrastructure, change spending limits, request payment details or present a paid plan as the solution. Local macOS/Xcode building is supported by the existing build scripts. Hosted capacity restrictions remain a release blocker until a genuinely free build host is available. Do not publish the private repository, source or signing material to obtain free capacity without explicit permission.

Hosted build workflows are manual-only. Pushing code or opening a pull request must not start hosted resource usage automatically. A manual hosted build is allowed only on genuinely free capacity; the workflow is not permission to incur charges.

This requirement does not reduce the professional-use acceptance standard in PRODUCTION_ACCEPTANCE.md. Keep the delivered IPA's actual version distinct from newer verified source until compilation and device checks succeed.
