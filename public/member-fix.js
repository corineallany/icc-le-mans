(function(){
'use strict';
const $=id=>document.getElementById(id);
function ensureArrival(){
  if($('mArrivalMonth')) return;
  const old=$('mFirstSeen');
  if(!old) return;
  old.closest('.field')?.insertAdjacentHTML('afterend',`<div class="field full"><label>Première arrivée dans l’église</label><div class="arrival-grid"><select id="mArrivalMonth" required><option value="">Mois *</option>${['Janvier','Février','Mars','Avril','Mai','Juin','Juillet','Août','Septembre','Octobre','Novembre','Décembre'].map((m,i)=>`<option value="${i+1}">${m}</option>`).join('')}</select><input id="mArrivalYear" type="number" min="1900" max="2100" required placeholder="Année *"><input id="mArrivalDay" type="number" min="1" max="31" placeholder="Jour (optionnel)"></div></div>`);
  old.closest('.field').style.display='none';
}
window.openMemberModal=function(id=null){
  ensureArrival();
  const m=id?peopleCache.find(x=>x.id===id):null;
  $('memberModalTitle').textContent=m?'Modifier la fiche':'Nouvelle personne / nouveau membre';
  $('mId').value=m?.id||'';$('mFirst').value=m?.first_name||'';$('mLast').value=m?.last_name||'';$('mEmail').value=m?.email||'';$('mPhone').value=m?.phone||'';$('mBirth').value=m?.birth_date||'';$('mGender').value=m?.gender||'';$('mJourney').value=m?.journey_status||'nouveau';$('mFamilySituation').value=m?.family_situation||'';$('mAddress1').value=m?.address_line1||'';$('mPostal').value=m?.postal_code||'';$('mCity').value=m?.city||'';$('mCountry').value=m?.country||'France';$('mInterests').value=(m?.interests||[]).join(', ');$('mSkills').value=(m?.skills||[]).join(', ');$('mAvailability').value=(m?.availability_tags||[]).join(', ');$('mNotes').value=m?.notes||'';
  const fs=m?.first_seen_at?new Date(m.first_seen_at):null;
  $('mArrivalMonth').value=m?.first_arrival_month|| (fs?fs.getMonth()+1:'');
  $('mArrivalYear').value=m?.first_arrival_year|| (fs?fs.getFullYear():'');
  $('mArrivalDay').value=m?.first_arrival_day||'';
  $('memberModal').classList.remove('hidden');
};
const form=$('memberForm');
if(form){form.onsubmit=async e=>{
  e.preventDefault();ensureArrival();
  const id=$('mId').value||null,month=Number($('mArrivalMonth').value),year=Number($('mArrivalYear').value),day=$('mArrivalDay').value?Number($('mArrivalDay').value):null;
  if(!month||!year)return alert('Le mois et l’année de première arrivée sont obligatoires.');
  const payload={first_name:$('mFirst').value.trim(),last_name:$('mLast').value.trim(),email:$('mEmail').value.trim()||null,phone:$('mPhone').value.trim()||null,birth_date:$('mBirth').value||null,gender:$('mGender').value||null,journey_status:$('mJourney').value,family_situation:$('mFamilySituation').value.trim()||null,address_line1:$('mAddress1').value.trim()||null,postal_code:$('mPostal').value.trim()||null,city:$('mCity').value.trim()||null,country:$('mCountry').value.trim()||'France',first_arrival_month:month,first_arrival_year:year,first_arrival_day:day,first_seen_at:new Date(Date.UTC(year,month-1,day||1)).toISOString(),interests:arr($('mInterests').value),skills:arr($('mSkills').value),availability_tags:arr($('mAvailability').value),notes:$('mNotes').value.trim()||null};
  const{data,error}=await db.rpc('save_member_record',{p_member_id:id,p_payload:payload});
  if(error)return alert(error.message);
  closeModal('memberModal');await loadPeople();await loadCounts();if(data)openPerson(data);
};}
setTimeout(()=>{ensureArrival();document.querySelectorAll('button').forEach(b=>{if((b.textContent||'').includes('Nouvelle personne'))b.onclick=()=>openMemberModal();});},300);
})();