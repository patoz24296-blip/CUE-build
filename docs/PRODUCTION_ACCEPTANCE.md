# Professional rehearsal acceptance

CUE is intended for preparing scenes and repeated working rehearsals. A passing build, a clean interface or a high test count alone is not a professional release. The delivered IPA must contain the verified source, and real iPhone rehearsal evidence must accompany the release claim.

## Rehearsal behavior

- Confirm the scene language, visible cast/pace and listening readiness before beginning. Audition each partner voice rather than treating a guessed casting assignment as a confirmed choice.
- Choose Off book or Follow script before starting. Follow script must track the active line and recognized words without trapping the actor when they scroll manually. Help, pause/resume, retry and ending the run must remain usable with enlarged text.
- An unfinished exact prefix must survive dramatic pauses in every accuracy mode. A missing end must not be accepted by the flexible-evaluation fallback.
- Changed names, times, numbers and negation must remain protected. The recognizer receives audio, never the expected script. Recognition disagreements or unverified mismatches require review, not a silent rewrite of what the actor said.
- Retry clears the current hearing and keeps the scene position without recording a failed attempt. An intentional skip remains an explicit, recorded choice. Hint use remains in the report.
- A review action must not apply to a later line after duplicate taps, a pause or a stale model response. Neither delayed permission nor delayed capture opening may leave the microphone recording after a stop.
- Returning from the background requires an explicit resume. Finishing preparation or a repeat countdown while backgrounded must not start the scene automatically.
- Recording is opt-in, visibly indicated in both views and exported/deleted through the existing local workflow. Script/history migrations must preserve existing data.

These behaviors have automated engine, recorder-lifecycle, database and phone-layout checks. Build 5 passed 120 default tests plus the separately enabled real native partner-quality test. The current installed simulator evidence is still build 3, not build 5.

## Physical iPhone 16e release evidence still required

Use IPHONE_SMOKE_TEST.md with the actual build number and iOS version. Validate a representative English script and a Spanish scene, each selected explicitly. Complete a sustained rehearsal through speaker and headphones, test background/calls/locks and Bluetooth changes, and repeat offline. Check first-cue and subsequent-cue delays, audible voice quality, clipped/missing speech, missed/false turns and recognition disagreements against the audio. Record actual outcomes; do not substitute host timings or synthesized-speech re-transcription for human listening and live microphone testing.

Kokoro provides neural speech with supported pace/volume/pauses. Arbitrary emotional acting, voice cloning and automatic switching inside a bilingual line are not implemented. Model descriptions and UI copy must state the supported behavior. A release cannot be called hardware-validated or final until the new IPA is built, installed and these checks are completed.
