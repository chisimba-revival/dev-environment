/** Shared Chisimba events and Mux adapter. @author Derek Keats */
(() => {
  document.querySelectorAll('[data-chisimba-video]').forEach(async shell => {
    if (shell.dataset.bound) return;
    shell.dataset.bound = '1';
    const player = shell.querySelector('mux-player'), status = shell.querySelector('[role=status]');
    const retry = shell.querySelector('[data-video-retry]');
    let busy = false, lastReport = 0, renewal, initial = true;
    const emit = (name, data = {}) => shell.dispatchEvent(new CustomEvent('chisimba:video:' + name, {bubbles: true, detail: {videoId: shell.dataset.id, ...data}}));
    async function authorise() {
      retry.disabled = true;
      try {
        const response = await fetch(shell.dataset.playback, {credentials: 'same-origin', cache: 'no-store'});
        const result = await response.json();
        if (!response.ok || !result.ok) throw new Error(result.message || shell.dataset.error);
        await customElements.whenDefined('mux-player');
        const grant = result.playback;
        player.tokens = {playback: grant.token, thumbnail: grant.thumbnail_token, storyboard: grant.storyboard_token};
        if (initial) {
          player.setAttribute('playback-id', grant.playback_id);
          player.addEventListener('loadedmetadata', () => { player.currentTime = Math.min(grant.position, Math.max(0, grant.duration - 1)); }, {once: true});
          initial = false;
        }
        clearTimeout(renewal);
        renewal = setTimeout(authorise, Math.max(1000, grant.expires * 1000 - Date.now() - 60000));
        status.textContent = ''; emit('ready');
      } catch (error) { player.pause(); status.textContent = error.message || shell.dataset.error; emit('error'); }
      finally { retry.disabled = false; }
    }
    async function report(playing) {
      if (!shell.dataset.consumer || busy || !Number.isFinite(player.currentTime)) return;
      busy = true; lastReport = Date.now();
      const body = new FormData();
      for (const key of ['id', 'consumer', 'reference']) body.set(key, shell.dataset[key]);
      body.set('csrf_token', shell.dataset.csrf); body.set('position', String(player.currentTime)); body.set('playing', playing ? '1' : '0');
      try {
        const response = await fetch(shell.dataset.progress, {method: 'POST', body, credentials: 'same-origin', keepalive: true});
        const result = await response.json();
        if (!response.ok || !result.ok) throw new Error(result.message || shell.dataset.error);
        shell.dataset.csrf = result.csrf; emit('progress', result.progress);
      } catch (error) { status.textContent = error.message || shell.dataset.error; }
      finally { busy = false; }
    }
    for (const name of ['play','pause','ended','seeking','seeked','error']) player.addEventListener(name, () => {
      emit(name);
      if (['play','seeked'].includes(name)) report(false);
      if (['pause','ended'].includes(name)) report(true);
      if (name === 'error') status.textContent = shell.dataset.error;
    });
    player.addEventListener('timeupdate', () => { if (!player.paused && !player.seeking && Date.now() - lastReport >= 10000) report(true); });
    document.addEventListener('visibilitychange', () => { if (document.hidden) report(!player.paused); });
    retry.addEventListener('click', authorise);
    authorise();
  });
})();
