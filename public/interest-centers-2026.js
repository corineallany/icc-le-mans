(function(){'use strict';
const $=id=>document.getElementById(id);
const esc=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
const fullName=p=>[p?.first_name,p?.last_name].filter(Boolean).join(' ')||'Personne';
let centers=[];
async function loadCenters(){
  const {data,error}=await db.from('interest_centers').select('id,name,description,display_order,active').eq('active',true).order('display_order').order('name');
  if(error) throw error;
  centers=data||[];
  return centers;
}
function showPanel(){
  if(typeof isolatePanel==='function') return isolatePanel('interestCentersHub');
  document.querySelectorAll('.panel').forEach(el=>{el.style.removeProperty('display');el.classList.toggle('on',el.id==='interestCentersHub')});
  document.querySelectorAll('[data-panel]').forEach(b=>b.classList.toggle('on',b.dataset.panel==='interestCentersHub'));
}
function ensureHub(){
  if($('interestCentersHub')) return;
  const p=document.createElement('section');
  p.id='interestCentersHub';
  p.className='panel';
  p.innerHTML='<div class="top"><div><h1>Centres d’intérêt</h1><p>Module transversal ICC + EJP pour constituer des groupes et organiser des activités.</p></div><button class="btn primary" onclick="addInterestCenter()">+ Ajouter</button></div><div id="interestHubBody"></div>';
  document.querySelector('main.main')?.appendChild(p);
}
async function getLinks(){
  const {data,error}=await db.from('member_interest_centers').select('member_id,interest_center_id').eq('active',true);
  if(error) throw error;
  return data||[];
}
window.renderInterestHub=async function(){
  ensureHub();
  const body=$('interestHubBody');
  if(!body) return;
  body.innerHTML='<div class="card">Chargement…</div>';
  try{
    const [list,links]=await Promise.all([loadCenters(),getLinks()]);
    const counts=new Map();
    for(const l of links) counts.set(l.interest_center_id,(counts.get(l.interest_center_id)||0)+1);
    body.innerHTML=`<div class="card">${list.map(c=>`<div class="interest-row"><button class="access-item" onclick="showInterestMembers('${c.id}')"><b>${esc(c.name)}</b><small>${counts.get(c.id)||0} personne(s)${c.description?' · '+esc(c.description):''}</small></button><button class="btn" onclick="editInterestCenter('${c.id}')">Modifier</button><button class="btn danger" onclick="disableInterestCenter('${c.id}')">Supprimer</button></div>`).join('')||'<p class="muted">Aucun centre d’intérêt.</p>'}</div>`;
  }catch(err){
    console.error('interest centers',err);
    body.innerHTML=`<div class="card"><p><b>Impossible de charger les centres d’intérêt.</b></p><p class="muted">${esc(err?.message||err)}</p><button class="btn" onclick="renderInterestHub()">Réessayer</button></div>`;
  }
};
window.openInterestCenters=async function(){ensureHub();showPanel();await window.renderInterestHub()};
window.showInterestMembers=async function(id){
  ensureHub();
  const body=$('interestHubBody');
  try{
    if(!centers.length) await loadCenters();
    const c=centers.find(x=>x.id===id);
    const {data:links,error}=await db.from('member_interest_centers').select('member_id').eq('interest_center_id',id).eq('active',true);
    if(error) throw error;
    const ids=[...new Set((links||[]).map(x=>x.member_id).filter(Boolean))];
    let members=[];
    if(ids.length){
      const r=await db.from('members').select('id,first_name,last_name').in('id',ids);
      if(r.error) throw r.error;
      members=(r.data||[]).sort((a,b)=>fullName(a).localeCompare(fullName(b),'fr',{sensitivity:'base'}));
    }
    body.innerHTML=`<button class="btn" onclick="renderInterestHub()">← Tous les centres</button><div class="card" style="margin-top:14px"><h2>${esc(c?.name||'Centre d’intérêt')}</h2>${members.map(p=>`<button class="access-item" onclick="openPerson('${p.id}')"><b>${esc(fullName(p))}</b></button>`).join('')||'<p class="muted">Aucun membre.</p>'}</div>`;
  }catch(err){body.innerHTML=`<button class="btn" onclick="renderInterestHub()">← Tous les centres</button><div class="card"><p><b>Impossible de charger les membres.</b></p><p class="muted">${esc(err?.message||err)}</p></div>`}
};
window.addInterestCenter=async function(){const name=prompt('Nom du centre d’intérêt :');if(!name?.trim())return;const description=prompt('Description (optionnelle) :')||null;const {error}=await db.from('interest_centers').insert({name:name.trim(),description,created_by:currentUser?.id||null});if(error)return alert(error.message);await renderInterestHub()};
window.editInterestCenter=async function(id){if(!centers.length)await loadCenters();const c=centers.find(x=>x.id===id);if(!c)return;const name=prompt('Nom :',c.name);if(!name?.trim())return;const description=prompt('Description :',c.description||'')||null;const {error}=await db.from('interest_centers').update({name:name.trim(),description,updated_at:new Date().toISOString()}).eq('id',id);if(error)return alert(error.message);await renderInterestHub()};
window.disableInterestCenter=async function(id){if(!confirm('Supprimer ce centre d’intérêt ? Les anciennes associations seront conservées mais masquées.'))return;const {error}=await db.from('interest_centers').update({active:false,updated_at:new Date().toISOString()}).eq('id',id);if(error)return alert(error.message);await renderInterestHub()};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',ensureHub);else ensureHub();
})();
