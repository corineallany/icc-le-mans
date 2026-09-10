(function(){'use strict';
const main=()=>document.querySelector('main.main');
function isolate(active){const m=main();if(!m||!active)return;[...m.children].forEach(el=>{if(el.tagName==='SECTION'&&el.classList.contains('panel')){const on=el===active;el.classList.toggle('on',on);el.style.display=on?'block':'none'}})}
function cleanEntity(){const app=document.getElementById('entityApp');if(!app||!app.classList.contains('on'))return;isolate(app);const subtitle=app.querySelector('.entity-hero .muted')?.textContent||'';const generic=/espace métier autonome/i.test(subtitle);if(generic){app.querySelectorAll('[data-etab]').forEach(b=>{if((b.dataset.etab||b.textContent).trim()==='Paramètres')b.remove()})}
}
function cleanGlobal(){const m=main();if(!m)return;const on=[...m.children].find(el=>el.tagName==='SECTION'&&el.classList.contains('panel')&&el.classList.contains('on'));if(on)isolate(on)}
document.addEventListener('click',e=>{const tab=e.target.closest('[data-etab]');if(tab)setTimeout(cleanEntity,0);const nav=e.target.closest('[data-panel]');if(nav)setTimeout(cleanGlobal,0)},true);
const obs=new MutationObserver(()=>{const app=document.getElementById('entityApp');if(app?.classList.contains('on'))cleanEntity()});obs.observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:['class']});
setTimeout(()=>{cleanGlobal();cleanEntity()},0);
})();