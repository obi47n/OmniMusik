# OmniMusik Wiki

The operational reference: where everything is, what it is called, and how to run,
deploy and tear it down. Nothing here is secret — every value on these pages is
either public by construction (a URL, a Cognito client id secured by PKCE, an ARN
that names a role) or an identifier that grants nothing on its own. Passwords and
keys never appear here; the page that mentions one says where it actually lives.

| Page | What it holds |
|---|---|
| [Environments and URLs](Environments-and-URLs.md) | Every endpoint, hostname, identifier and ARN, for production and local |
| [Deploying](Deploying.md) | How a change reaches AWS: by hand and through CI |
| [Running locally](Running-Locally.md) | Backend, web client and the phone, on this machine |
| [Costs and teardown](Costs-and-Teardown.md) | What it costs to leave running, and the order to destroy it in |

## Other documents

| Document | Purpose |
|---|---|
| [System design](../system-design.html) | Architecture with diagrams: context, iOS layers, playback, sync, deployment ([published](https://claude.ai/code/artifact/140c4904-8d3b-42ac-ab08-b67a45d5d6c4)) |
| [Screens](../showcase.html) | Screenshot showcase of the iOS app and web companion, images embedded ([published](https://claude.ai/code/artifact/98c83a0d-3d60-4159-8a4d-9adb123a43ac)) |
| [Field guide](../field-guide.html) | The project in ten minutes, for interview study ([published](https://claude.ai/code/artifact/c0676296-9d95-4f78-92c4-9017d1a53920)) |
| [Talking points](../talking-points.html) | Interview preparation: the questions this project attracts and the answers worth giving ([published](https://claude.ai/code/artifact/70922f61-74bf-4fa4-8068-eb2feb786aa3)) |
| [Interview notes](../interview-notes.html) | The long-form study document ([published](https://claude.ai/code/artifact/f4b69ae6-fc9c-477a-b3d9-92eb0f566fa4)) |
| [DECISIONS.md](../../DECISIONS.md) | Every non-obvious choice, with the alternatives rejected |
| [CLAUDE.md](../../CLAUDE.md) | Working notes for the codebase: constraints, conventions, traps |

## Repository

- GitHub: https://github.com/obi47n/OmniMusik (branch `master`)
- iOS bundle id: `com.obinnaduruaku.OmniMusik`
- AWS account `463092208222`, region `us-east-1`

## Keeping this current

Infrastructure changes should update [Environments and URLs](Environments-and-URLs.md)
in the same commit. The one value most likely to move is the API endpoint: it is
assigned by ECS when the Express service is created, so a deleted-and-recreated
service gets a new hostname, and three places then need it — `APIConfiguration.swift`,
`web/.env.local`, and the `VITE_API_BASE_URL` repository variable on GitHub.
