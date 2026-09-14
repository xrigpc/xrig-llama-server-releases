# RX 7900 XTX release process

`Build & Release — RX 7900 XTX (ROCm gfx1100)` accepts only a full approved
llama.cpp SHA, positive revision, and the generated readable tag. It runs in
the protected `production` environment, signs with the existing XRIG Ed25519
format, and uploads only the XRIG runtime archive plus evidence to GitHub.

`Publish Profile — RX 7900 XTX (ROCm gfx1100)` is separate. It verifies the
GitHub receipt/signature, source ancestry, official AMD pin and GPU
qualification before writes. It creates immutable descriptor/config bytes,
updates the signed stack index, then updates the mutable catalogue last.
Neither workflow uploads a TheRock archive, models, drivers, or database
migrations.

The profile's TheRock URL is the official AMD nightly tarball URL. Its exact
size and SHA-256 are deliberate review inputs; changing either requires a new
profile review and immutable stack version.
