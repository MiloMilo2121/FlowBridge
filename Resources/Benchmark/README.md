# Benchmark cases

Drop paired files here to feed `BenchmarkHarness`:

- `<name>.wav` (or `.m4a`, `.mp3`, `.caf`) — the recorded speech.
- `<name>.txt` — the reference transcript, plain UTF-8.

Record the Italian test set on the target device (normal voice, whisper,
street noise, technical vocabulary) so engine comparisons reflect real
usage. WER tokenization is case- and punctuation-insensitive, so the
reference only needs the right words in the right order.

This folder ships empty on purpose; audio files are not committed.
