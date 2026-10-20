/** Direct, resumable uploads; never proxy original video bytes. @author Derek Keats */
(() => {
  const form = document.querySelector('[data-video-upload]');
  if (!form) return;
  const status = form.querySelector('[role=status]'), progress = form.querySelector('progress'), submit = form.querySelector('[type=submit]');
  document.querySelectorAll('form[method=post]').forEach(editor => {
    if (editor === form) return;
    const notice = document.createElement('p'); notice.setAttribute('role', 'status'); editor.append(notice);
    editor.addEventListener('submit', async event => {
      event.preventDefault(); const buttons = editor.querySelectorAll('button'); buttons.forEach(button => { button.disabled = true; });
      const body = new FormData(editor); body.set('ajax', '1');
      try {
        const response = await fetch(editor.action, {method: 'POST', body, credentials: 'same-origin'});
        if (!(response.headers.get('content-type') || '').includes('application/json')) throw new Error(form.dataset.error);
        if (!(response.headers.get('content-type') || '').includes('application/json')) throw new Error(form.dataset.error);
      const result = await response.json(); if (!response.ok || !result.ok) throw new Error(result.message || form.dataset.error);
        window.location.reload();
      } catch (error) { notice.textContent = error.message || form.dataset.error; buttons.forEach(button => { button.disabled = false; }); }
    });
  });
  const pause = form.querySelector('[data-upload-pause]'), resume = form.querySelector('[data-upload-resume]');
  form.addEventListener('submit', async event => {
    event.preventDefault();
    const file = form.querySelector('[type=file]').files[0]; if (!file) return;
    submit.disabled = true; status.textContent = form.dataset.authorising;
    try {
      const body = new FormData(form); body.delete('video_file');
      const response = await fetch(form.action, {method: 'POST', body, credentials: 'same-origin'});
      const result = await response.json(); if (!response.ok || !result.ok) throw new Error(result.message || form.dataset.error);
      document.querySelectorAll('input[name=csrf_token]').forEach(input => { input.value = result.csrf; });
      const upload = UpChunk.createUpload({endpoint: result.upload.url, file, chunkSize: 8192});
      status.textContent = form.dataset.uploading; progress.hidden = false; pause.hidden = false;
      pause.onclick = () => { upload.pause(); pause.hidden = true; resume.hidden = false; };
      resume.onclick = () => { upload.resume(); resume.hidden = true; pause.hidden = false; };
      upload.on('progress', event => { progress.value = event.detail; });
      upload.on('error', () => { status.textContent = form.dataset.interrupted; pause.hidden = true; resume.hidden = true; });
      upload.on('success', () => { status.textContent = form.dataset.processing; window.location.assign(form.dataset.library); });
    } catch (error) { status.textContent = error.message || form.dataset.error; submit.disabled = false; }
  });
})();
