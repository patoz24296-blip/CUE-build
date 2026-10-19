# Physical iPhone smoke test

Build success is not evidence that a physical iPhone microphone or audio route works. Record the iPhone model, iOS version, commit/build number, signing account type and tested audio routes below when completing this checklist.

Device: _not yet tested_  
iOS: _not yet tested_  
Build: _not yet tested_

1. Download the release IPA from the successful macOS workflow and install using Sideloadly. Confirm its checksum. Launch on iOS 15.5 or later.
2. Import The Last Light. Confirm two roles, two scenes and sixteen dialogue lines. Review/edit a line, merge a character, correct a boundary, choose MARA, and restart the app to verify durable storage.
3. Install lightweight listening, recognition and voices. Cancel/retry one download. Confirm installed sizes and delete/reinstall recovery. On an older phone, watch memory and the first-response latency.
4. Rehearse the nighttime scene in Flexible. Listen through the phone speaker, say MARA's lines, and confirm own lines remain hidden and the next partner cue follows automatically.
5. Stop mid-sentence for at least five seconds. Confirm no advance from silence alone. Finish the line; confirm automatic progression. Compare Fast, Natural and Patient.
6. Say “CUE please” three times. Confirm progressive spoken hints, full-line long press, and accurate hint counts/results. Verify the phrase inside longer dialogue does not trigger a hint accidentally.
7. Say “I always loved her” for “I never loved her,” “eleven” for “seven,” and another name for “Ellis.” Confirm these are marked as meaningful/protected deviations. Try the harmless reordered line in Flexible/Loose.
8. End the run. Confirm saved attempts, textual accuracy, hints and response timing. Run it again; then drill weak lines. Accept a safe variation and verify it is rejected by Word Perfect and allowed by non-strict modes on a new run.
9. Rehearse with airplane mode enabled after downloads. Restart the app offline; confirm scripts, voices, recognition, evaluation and results remain functional.
10. Test microphone denial, later granting permission, a telephone/audio interruption, home/background/lock and resume. CUE must pause without advancing or continuing playback in the background.
11. Test wired and Bluetooth headphones; unplug mid-run. Confirm speaker routing, capture and pause recovery. Enable overlap with headphones and verify actor speech cuts the appropriate partner cue, while partner playback echo never advances the actor's line.
12. Increase system text size and CUE text size. Test VoiceOver state announcements, portrait/landscape safe areas and controls on the smallest supported phone. Confirm hidden dialogue is absent from VoiceOver semantics.
13. Delete rehearsal history. Scripts must remain. Delete a script. Its history must be removed. Confirm temporary microphone audio was never permanently recorded and temporary partner audio is removed after leaving a run.

Result: _pending physical device evidence_


## Completed-feature hardware checks

- Run all scenes, a selected range, and custom Line Drill; verify each scene boundary and hidden actor dialogue.
- Set a character/scene direction and Full Performance; confirm partner pacing, pauses and volume. Compare consistent timing.
- Use a custom two-word hint command, pause/resume, request another hint, and confirm both requests and times in results.
- Enable recording explicitly, perform a scene, play the mixed WAV, export through Files, and delete it. Test interrupted recording and retention cleanup. Confirm recording-off creates no microphone WAV.
- Export CSV and JSON, review progress trends, edit one line, and verify its off-book status resets while historical text remains unchanged.
- Repeat the same acceptable alternative three times and exercise accept, keep flagging, edit and later. Strict mode must still require script wording.
- Select multilingual recognition after installing it and test a chosen language. Select a Bluetooth/external microphone if present and reconnect it during practice.
- Install optional meaning/embedding components; verify a safe paraphrase and changed protected number. Disconnect internet and repeat.
