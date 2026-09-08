(function(){
'use strict';
const $=id=>document.getElementById(id);
const role=()=>typeof currentProfile!=='undefined'?(currentProfile?.role||''):'';
const isEditor=()=>['admin','pasteur'].includes(role());
function exposeSettings(){
  const sec=$('settings'); if(sec){sec.classList.remove('admin-only');sec.style.display='';}
  const btn=document.querySelector('.nav button[data-panel="settings"]');
  if(btn){btn.classList.remove('admin-only');btn.style.display='block';}
  const sep=btn?.previousElementSibling;if(sep?.classList.contains('sep')){sep.classList.remove('admin-only');sep.style.display='block';}
}
async function refreshIdentity(){
  if(typeof currentProfile==='undefined'||!currentProfile?.member_id||typeof db==='undefined')return;
  const{data:m}=await db.from('members').select('id,first_name,last_name,email').eq('id',currentProfile.member_id).maybeSingle();
  if(!m)return;
  currentProfile.first_name=m.first_name; currentProfile.last_name=m.last_name;
  const n=$('userName');if(n)n.textContent=[m.first_name,m.last_name].filter(Boolean).join(' ')||'Utilisateur';
  const av=$('avatar');if(av)av.textContent=(m.first_name?.[0]||'I')+(m.last_name?.[0]||'C');
  if(typeof buildAccessMenu==='function')buildAccessMenu();
}
function lockReadOnly(){
  if(isEditor())return;
  const panel=$('settings');if(!panel)return;
  panel.querySelectorAll('input,select,textarea').forEach(el=>el.disabled=true);
  panel.querySelectorAll('button').forEach(btn=>{if(btn.dataset.settingsTab)return;const t=(btn.textContent||'').toLowerCase();if(/enregistrer|accepter|refuser|suspendre|créer|ajouter|modifier|supprimer/.test(t))btn.style.display='none';});
  if(!$('settingsReadOnlyNote')){const n=document.createElement('div');n.id='settingsReadOnlyNote';n.className='notice';n.textContent='Consultation uniquement — les modifications des paramètres sont réservées à l’administratrice et au Pasteur.';$('settingsPane')?.parentElement?.insertBefore(n,$('settingsPane'));}
}
async function renderReadonlySettings(){
  const pane=$('settingsPane');if(!pane)return;
  const tab=typeof settingsTab!=='undefined'?settingsTab:'organization';
  if(tab==='organization'){
    const[{data:s},{data:l}]=await Promise.all([db.from('church_settings').select('*').eq('key','organization').maybeSingle(),db.from('unit_leadership_assignments').select('organization_unit_id,leadership_role,members(first_name,last_name)').eq('active',true)]);
    const pid=s?.value?.pastor_member_id,pm=(typeof peopleCache!=='undefined'?peopleCache:[]).find(x=>x.id===pid);const byCode=c=>(typeof allUnits!=='undefined'?allUnits:[]).find(x=>x.code===c);const children=c=>{const p=byCode(c);return p?(typeof allUnits!=='undefined'?allUnits:[]).filter(x=>x.parent_id===p.id):[]};
    const block=(title,rows)=>`<div class="card"><h3>${title}</h3>${rows.map(u=>{const rr=(l||[]).filter(x=>x.organization_unit_id===u.id);return `<div class="info-row"><b>${u.name}</b><small>${rr.map(x=>`${String(x.leadership_role).replaceAll('_',' ')} : ${[x.members?.first_name,x.members?.last_name].filter(Boolean).join(' ')||'à définir'}`).join(' · ')||'Responsables à définir'}</small></div>`}).join('')||'<p class="muted">Aucune entité.</p>'}</div>`;
    pane.innerHTML=`<div class="card"><h2 class="section-title">Organisation de l’église</h2><div class="info-row"><small>Pasteur</small><b>${pm?[pm.first_name,pm.last_name].filter(Boolean).join(' '):'À définir'}</b></div></div><div class="units" style="margin-top:14px">${block('Ministères',children('CAT_MINISTERES'))}${block('Dynamiques',children('CAT_DYNAMIQUES'))}${block('Départements',children('CAT_DEPARTEMENTS'))}</div>`;
  } else if(tab==='leaders'){
    const{data:l}=await db.from('unit_leadership_assignments').select('organization_unit_id,leadership_role,members(first_name,last_name),organization_units(name)').eq('active',true);
    pane.innerHTML=`<div class="card"><h2 class="section-title">Responsables & adjoints</h2>${(l||[]).map(x=>`<div class="info-row"><b>${x.organization_units?.name||'Unité'}</b><small>${String(x.leadership_role).replaceAll('_',' ')} · ${[x.members?.first_name,x.members?.last_name].filter(Boolean).join(' ')||'—'}</small></div>`).join('')||'<p class="muted">Aucune responsabilité configurée.</p>'}</div>`;
  } else if(tab==='access'){
    pane.innerHTML='<div class="card"><h2 class="section-title">Utilisateurs & accès</h2><p>Les rôles, périmètres et droits de gestion sont configurés ici. La liste détaillée des comptes et actions sensibles est réservée à l’administratrice et au Pasteur.</p></div>';
  } else if(tab==='programs'){
    pane.innerHTML='<div class="units"><div class="card"><h2>Calendrier global</h2><p>Les programmes visibles globalement alimentent le calendrier commun.</p></div><div class="card"><h2>Administration programme</h2><p>Fiche complète, équipe du jour, déroulé, unités et préparation.</p></div><div class="card"><h2>Droits</h2><p>La gestion dépend des accès et responsabilités configurés.</p></div></div>';
  } else if(tab==='notifications'){
    pane.innerHTML='<div class="units"><div class="card"><h2>Demandes d’accès</h2><p>Alertes liées aux demandes de compte.</p></div><div class="card"><h2>Intégration</h2><p>Alertes de transmission et de suivi.</p></div><div class="card"><h2>Push</h2><p>Appareils et préférences de notification.</p></div></div>';
  }
  lockReadOnly();
}
async function showSettings(){exposeSettings();if(isEditor()&&typeof renderSettings==='function')await renderSettings();else await renderReadonlySettings();lockReadOnly();}
function wire(){
  exposeSettings();
  const sbtn=document.querySelector('.nav button[data-panel="settings"]');if(sbtn)sbtn.addEventListener('click',()=>setTimeout(showSettings,30),true);
  document.querySelectorAll('[data-settings-tab]').forEach(b=>b.addEventListener('click',()=>setTimeout(showSettings,30),true));
  const pbtn=document.querySelector('.nav button[data-panel="people"]');if(pbtn)pbtn.addEventListener('click',()=>setTimeout(()=>{if(typeof loadPeople==='function')loadPeople();},30),true);
  ['ministries','dynamics','departments'].forEach(id=>{const b=document.querySelector(`.nav button[data-panel="${id}"]`);if(b)b.addEventListener('click',()=>setTimeout(()=>{if(typeof loadUnits==='function')loadUnits();},30),true);});
  setInterval(exposeSettings,1200);
}
setTimeout(async()=>{wire();if(typeof loadPeople==='function')await loadPeople();if(typeof loadUnits==='function')await loadUnits();await refreshIdentity();exposeSettings();},450);
})();
