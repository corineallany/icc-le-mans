(function(){'use strict';
const $=id=>document.getElementById(id), E=s=>String(s??'').replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[m]));
let portals=[],activePortal=null,portalMemberships=new Map(),portalAccess=[];
const globalRole=()=>['admin','pasteur'].includes(currentProfile?.role);
const portalOfCode=code=>portals.find(x=>x.code===code);
async function loadPortalData(){
  const [p,m,a]=await Promise.all([
    db.from('church_portals').select('*').eq('active',true).order('display_order'),
    db.from('member_church_affiliations').select('member_id,portal_id,active').eq('active',true),
    currentUser?.id?db.from('profile_portal_access').select('portal_id,can_view,can_manage,can_view_sensitive,active').eq('profile_id',currentUser.id).eq('active',true):Promise.resolve({data:[]})
  ]);
  portals=p.data||[]; portalAccess=a.data||[]; portalMemberships=new Map();
  for(const x of m.data||[]){const arr=portalMemberships.get(x.member_id)||[];arr.push(x.portal_id);portalMemberships.set(x.member_id,arr)}
  window.churchPortals=portals;window.portalMemberships=portalMemberships;
}
function canPortal(p){
  if(globalRole())return true;
  if(portalAccess.some(a=>a.portal_id===p.id&&a.can_view))return true;
  return (myAssignments||[]).some(a=>{const u=(allUnits||[]).find(x=>x.id===a.organization_unit_id);return u?.portal_id===p.id});
}
function ensureFacade(){
  if(!$('portalFacade')){const s=document.createElement('section');s.id='portalFacade';s.className='panel';document.querySelector('main.main')?.appendChild(s)}
  if(!$('portal2026Style')){const st=document.createElement('style');st.id='portal2026Style';st.textContent='.portal-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;max-width:1050px}.portal-card{padding:28px;min-height:220px;display:flex;flex-direction:column;justify-content:space-between}.portal-card h2{font-size:25px;margin:4px 0 8px}.portal-mark{font-size:12px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:var(--blue)}.portal-switch{border:1px solid var(--line);background:#fff;border-radius:10px;padding:7px 10px;color:var(--blue);font-weight:800;margin-right:auto}.global-card{margin-top:18px;max-width:1050px}.portal-context{font-size:11px;color:var(--muted);margin-top:4px}@media(max-width:720px){.portal-grid{grid-template-columns:1fr}.portal-card{min-height:180px}}';document.head.appendChild(st)}
}
function showFacade(){
  ensureFacade();document.querySelectorAll('.panel').forEach(x=>x.classList.remove('on'));$('portalFacade').classList.add('on');
  const allowed=portals.filter(canPortal);
  $('portalFacade').innerHTML=`<div class="top"><div><h1>Portails d’église</h1><p>ICC Le Mans et l’Église des Jeunes Prodiges partagent une seule base de données, avec des organisations et pilotages séparés.</p></div></div><div class="portal-grid">${allowed.map(p=>`<div class="card portal-card"><div><span class="portal-mark">Portail ${E(p.code)}</span><h2>${E(p.name)}</h2><p class="muted">Bureau, départements, dynamiques, STAR, programmes, planning et statistiques propres à ce périmètre.</p></div><button class="btn primary" onclick="selectChurchPortal('${p.code}')">Accéder au portail ${E(p.code)}</button></div>`).join('')||'<div class="card">Aucun portail de pilotage ne vous est actuellement attribué.</div>'}</div>${globalRole()?`<div class="card global-card"><div class="top"><div><span class="portal-mark">Gouvernance</span><h2>Vision globale ICC + EJP</h2><p class="muted">Vue consolidée des deux églises. Une personne ICC + EJP reste une seule personne dans le total global.</p></div><button class="btn" onclick="selectChurchPortal('GLOBAL')">Ouvrir la vision globale</button></div></div>`:''}`;
}
function setBrand(){
  const b=document.querySelector('.brand');if(!b)return;const label=activePortal==='GLOBAL'?'ICC + EJP':portalOfCode(activePortal)?.name||'ICC Le Mans';
  b.innerHTML=`${E(label)}<small>${activePortal==='GLOBAL'?'Pilotage consolidé':'Portail de pilotage'}</small>`;
  let sw=$('portalSwitch');if(!sw){sw=document.createElement('button');sw.id='portalSwitch';sw.className='portal-switch';document.querySelector('.topbar')?.prepend(sw)}
  sw.textContent=(activePortal==='GLOBAL'?'Vision globale':activePortal)+' ▾';sw.onclick=showFacade;
}
window.selectChurchPortal=async code=>{
  if(code!=='GLOBAL'){const p=portalOfCode(code);if(!p||!canPortal(p))return alert('Vous n’avez pas accès à ce portail.')}else if(!globalRole())return alert('La vision globale est réservée au Pasteur et à la gouvernance autorisée.');
  activePortal=code;window.activeChurchPortal=code;sessionStorage.setItem('icc_active_portal',code);setBrand();await window.loadUnits();if(typeof loadCounts==='function')await loadCounts();openPanel('dashboard');
};
window.getActivePortalId=()=>activePortal==='GLOBAL'?null:portalOfCode(activePortal)?.id||null;
window.filterByActivePortal=rows=>{if(activePortal==='GLOBAL'||!activePortal)return rows;const pid=portalOfCode(activePortal)?.id;return (rows||[]).filter(x=>x.scope_kind==='global'||x.portal_id===pid)};

const oldLoadUnits=window.loadUnits;
window.loadUnits=async function(){
  await oldLoadUnits();if(!portals.length)await loadPortalData();
  const pid=activePortal==='GLOBAL'?null:portalOfCode(activePortal)?.id;
  const visible=(allUnits||[]).filter(u=>u.scope_kind==='global'||activePortal==='GLOBAL'||!activePortal||u.portal_id===pid);
  const codes=activePortal==='EJP'?{m:'EJP_CAT_MINISTERES',d:'EJP_CAT_DYNAMIQUES',p:'EJP_CAT_DEPARTEMENTS'}:{m:'CAT_MINISTERES',d:'CAT_DYNAMIQUES',p:'CAT_DEPARTEMENTS'};
  const cat=code=>visible.find(x=>x.code===code)?.id;
  const render=(id,parent)=>{const box=$(id);if(!box)return;box.innerHTML=visible.filter(x=>x.parent_id===parent&&x.active!==false).sort((a,b)=>String(a.name).localeCompare(String(b.name),'fr')).map(u=>`<div class="card unit" onclick="openEntityById('${u.id}','Accueil')"><h2>${E(u.name)}</h2><small>${E(u.description||'Espace métier')}</small></div>`).join('')||'<div class="card">Aucune entité dans ce portail.</div>'};
  if(activePortal==='ICC'||activePortal==='EJP'){render('ministryCards',cat(codes.m));render('dynamicCards',cat(codes.d));render('departmentCards',cat(codes.p))}
  if(activePortal==='GLOBAL'){
    const note='<div class="notice">Vision globale : utilisez le sélecteur de portail en haut pour administrer les structures propres à ICC ou à EJP. Les Familles de disciples restent transversales.</div>';
    ['ministries','dynamics','departments'].forEach(id=>{const p=$(id);if(p&&!p.querySelector('.globalPortalNote')){const d=document.createElement('div');d.className='globalPortalNote';d.innerHTML=note;p.prepend(d)}})
  }
  setBrand();
};

function ensureMembershipField(){
  if($('mChurchMembership'))return;const anchor=$('mFirst')?.closest('.field');if(!anchor)return;
  anchor.insertAdjacentHTML('beforebegin',`<div class="field full" id="mChurchMembership"><label>Appartenance à l’église</label><div class="check-grid"><label class="check-item"><input type="checkbox" id="mPortalICC"> ICC Le Mans</label><label class="check-item"><input type="checkbox" id="mPortalEJP"> Église des Jeunes Prodiges (EJP)</label></div><small class="muted">Choisissez ICC, EJP ou les deux. La fiche personne reste unique.</small></div>`);
  if(!globalRole()){$('mPortalICC').disabled=true;$('mPortalEJP').disabled=true}
}
window.loadMemberPortalMembership=async id=>{
  ensureMembershipField();if(!$('mPortalICC')||!$('mPortalEJP'))return;$('mPortalICC').checked=!id;$('mPortalEJP').checked=false;if(!id)return;
  const {data,error}=await db.from('member_church_affiliations').select('portal_id,active').eq('member_id',id).eq('active',true);if(error)return console.error(error);
  const ids=new Set((data||[]).map(x=>x.portal_id));$('mPortalICC').checked=ids.has(portalOfCode('ICC')?.id);$('mPortalEJP').checked=ids.has(portalOfCode('EJP')?.id);
};
window.saveMemberPortalMembership=async id=>{
  ensureMembershipField();const wanted=[];if($('mPortalICC')?.checked)wanted.push(portalOfCode('ICC')?.id);if($('mPortalEJP')?.checked)wanted.push(portalOfCode('EJP')?.id);const clean=wanted.filter(Boolean);if(!clean.length)throw new Error('Choisissez ICC, EJP ou les deux.');
  const {data,error}=await db.from('member_church_affiliations').select('id,portal_id,active').eq('member_id',id);if(error)throw error;
  for(const p of portals){const want=clean.includes(p.id),row=(data||[]).find(x=>x.portal_id===p.id);let q;if(row)q=await db.from('member_church_affiliations').update({active:want,ends_at:want?null:new Date().toISOString().slice(0,10)}).eq('id',row.id);else if(want)q=await db.from('member_church_affiliations').insert({member_id:id,portal_id:p.id,active:true,starts_at:new Date().toISOString().slice(0,10)});if(q?.error)throw q.error}
  await loadPortalData();
};
async function addMembershipBadge(id){const host=$('personDetail');if(!host)return;let box=$('memberPortalBlock');if(!box){box=document.createElement('div');box.id='memberPortalBlock';box.className='card';box.style.marginTop='14px';host.appendChild(box)}const ids=portalMemberships.get(id)||[];const labs=portals.filter(p=>ids.includes(p.id)).map(p=>p.code);box.innerHTML=`<h3>Appartenance d’église</h3><div class="info-row"><small>Périmètre</small><b>${E(labs.length===2?'ICC + EJP':labs[0]||'Non renseigné')}</b></div>`}

const nativeRpc=db.rpc.bind(db);
db.rpc=function(fn,args,opts){
  if(fn==='save_member_record'&&args?.p_payload&&globalRole()){
    const codes=[];if($('mPortalICC')?.checked)codes.push('ICC');if($('mPortalEJP')?.checked)codes.push('EJP');
    if(codes.length)args={...args,p_payload:{...args.p_payload,church_codes:codes}};
  }
  return nativeRpc(fn,args,opts);
};

const baseOpenMember=window.openMemberModal;
window.openMemberModal=async function(id=null){await Promise.resolve(baseOpenMember?.(id));if(!portals.length)await loadPortalData();await loadMemberPortalMembership(id)};
const baseOpenPerson=window.openPerson;
window.openPerson=async function(id){const r=baseOpenPerson?.(id);await Promise.resolve(r);if(!portals.length)await loadPortalData();setTimeout(()=>addMembershipBadge(id),100);return r};

async function init(){await loadPortalData();ensureFacade();ensureMembershipField();activePortal=sessionStorage.getItem('icc_active_portal');if(!['ICC','EJP','GLOBAL'].includes(activePortal))activePortal=null;if(activePortal==='GLOBAL'&&!globalRole())activePortal=null;if(activePortal&&!globalRole()){const p=portalOfCode(activePortal);if(p&&!canPortal(p))activePortal=null}if(!activePortal)showFacade();else setBrand()}
const oldAll=window.loadAll;window.loadAll=async function(){await oldAll();await init()};
})();