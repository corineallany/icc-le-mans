(function(){
'use strict';
const $=id=>document.getElementById(id);
const isEditor=()=>['admin','pasteur'].includes(window.currentProfile?.role);
function exposeSettings(){
  const settingsBtn=document.querySelector('.nav button[data-panel="settings"]');
  if(settingsBtn){settingsBtn.classList.remove('admin-only');settingsBtn.style.display='block';}
  const sep=settingsBtn?.previousElementSibling;if(sep?.classList.contains('sep')){sep.classList.remove('admin-only');sep.style.display='block';}
}
function lockReadOnly(){
  if(isEditor()) return;
  const panel=$('settings'); if(!panel) return;
  panel.querySelectorAll('input,select,textarea').forEach(el=>{el.disabled=true;});
  panel.querySelectorAll('button').forEach(btn=>{
    if(btn.dataset.settingsTab) return;
    const t=(btn.textContent||'').toLowerCase();
    if(/enregistrer|accepter|refuser|suspendre|créer|ajouter|modifier|supprimer/.test(t)) btn.style.display='none';
  });
  let note=$('settingsReadOnlyNote');
  if(!note){note=document.createElement('div');note.id='settingsReadOnlyNote';note.className='notice';note.textContent='Consultation uniquement — les modifications des paramètres sont réservées à l’administratrice et au Pasteur.';const pane=$('settingsPane');pane?.parentElement?.insertBefore(note,pane);}
}
function patchSettingsRendering(){
  if(typeof window.renderSettings!=='function') return;
  const original=window.renderSettings;
  window.renderSettings=async function(){
    const role=window.currentProfile?.role;
    if(!['admin','pasteur'].includes(role)){
      // Existing renderer is admin-gated. Temporarily render using the same read path, then lock all editing controls.
      const p=window.currentProfile; window.currentProfile={...p,role:'admin'};
      try{await original.apply(this,arguments);}finally{window.currentProfile=p;}
      lockReadOnly(); return;
    }
    const r=await original.apply(this,arguments); lockReadOnly(); return r;
  };
}
function patchMenu(){
  const old=window.buildAccessMenu;
  if(typeof old!=='function') return;
  window.buildAccessMenu=function(){
    old.apply(this,arguments);
    const menu=$('accessMenu'); if(!menu) return;
    if(!menu.querySelector('[data-open-settings]')){
      const logout=[...menu.querySelectorAll('button')].find(b=>(b.textContent||'').toLowerCase().includes('déconnect'));
      const b=document.createElement('button');b.className='access-item';b.dataset.openSettings='1';b.innerHTML='<b>⚙ Paramètres</b><small>'+(isEditor()?'Configuration de l’application':'Consultation')+'</small>';b.onclick=()=>{if(typeof toggleAccess==='function')toggleAccess(false);openPanel('settings');setTimeout(lockReadOnly,80)};
      if(logout)menu.insertBefore(b,logout);else menu.appendChild(b);
    }
  };
}
function init(){exposeSettings();patchSettingsRendering();patchMenu();if(window.currentProfile)window.buildAccessMenu?.();const settingsBtn=document.querySelector('.nav button[data-panel="settings"]');settingsBtn?.addEventListener('click',()=>setTimeout(lockReadOnly,100));}
setTimeout(init,700);
})();
