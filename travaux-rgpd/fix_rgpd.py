# RGPD : copie Workday réduite au site, export / effacement des données d'une personne, page d'information
import sys
p=sys.argv[1]; s=open(p).read()
def rep(a,b,n=1):
    global s
    c=s.count(a); assert c==n,(p,c,a[:90]); s=s.replace(a,b)
COMP=r'''
// ════════════════ RGPD ════════════════
// Copie Workday : on ne garde que les personnes qui ont une fiche, et les arrivées récentes ou à venir
function wdMinimiser(cache,badges){
  if(!cache||typeof cache!=="object")return cache;
  const mats=new Set((badges||[]).filter(b=>b.statut!=="Archivé").map(b=>String(b.matricule||"").trim()).filter(m=>m&&m!=="0"&&m!=="NC"));
  const min=isoLocal(new Date(Date.now()-60*864e5));const out={};
  Object.keys(cache).forEach(k=>{const w=cache[k]||{};const h=String(w.hireDate||"").slice(0,10);
    if(mats.has(String(k).trim())||mats.has(String(w.matricule||"").trim())||(/^\d{4}-\d{2}-\d{2}$/.test(h)&&h>=min))out[k]=w;});
  return out;
}
// Droit d'accès et droit à l'effacement, depuis la fiche
function DonneesPersonne({fiche,showToast,setBadges,editingId,fermer}){
  const el=React.createElement;const[busy,setBusy]=useState(false);
  const nom=String(fiche.nom||"").trim(),prenom=String(fiche.prenom||"").trim(),email=String(fiche.email||"").trim();
  const admin=!!window._estAdmin;
  const exporter=async()=>{if(!nom){showToast("⚠️ Nom manquant","err");return;}setBusy(true);
    const out={personne:prenom+" "+nom,exporte_le:new Date().toISOString(),fiche,colis:[],field_support:[],prets_de_badges:[],casiers:[],journal:[]};
    const lc=x=>String(x||"").toLowerCase();const contient=t=>lc(t).includes(lc(nom))&&lc(t).includes(lc(prenom));
    try{if(sb){
      const q=async(f)=>{try{const r=await f();return r&&!r.error?(r.data||[]):[];}catch(e){return [];}};
      out.colis=(await q(()=>sb.from("lp24_colis").select("*").ilike("nom",nom))).filter(c=>lc(c.prenom)===lc(prenom)||(email&&lc(c.email)===lc(email)));
      out.field_support=(await q(()=>sb.from("lp24_fss").select("*").ilike("nom",nom))).filter(f=>lc(f.prenom)===lc(prenom));
      out.prets_de_badges=(await q(()=>sb.from("badges_pret_histo").select("*").ilike("emprunteur","%"+nom+"%"))).filter(x=>contient(x.emprunteur));
      out.casiers=(await q(()=>sb.from("lp24_casiers_journal").select("*").ilike("personne","%"+nom+"%"))).filter(x=>contient(x.personne));
      out.journal=(await q(()=>sb.from("historique").select("*").ilike("detail","%"+nom+"%").limit(1000))).filter(x=>contient(x.detail));
    }}catch(e){}
    const blob=new Blob([JSON.stringify(out,null,2)],{type:"application/json"});const a=document.createElement("a");
    a.href=URL.createObjectURL(blob);a.download="donnees-"+nom.toUpperCase()+"-"+prenom+".json";document.body.appendChild(a);a.click();a.remove();
    setBusy(false);showToast("📄 Données exportées ("+(1+out.colis.length+out.field_support.length+out.prets_de_badges.length+out.casiers.length+out.journal.length)+" éléments)");};
  const effacer=async()=>{
    if(!confirm("Effacer DÉFINITIVEMENT toutes les données de "+prenom+" "+nom.toUpperCase()+" ?\n\nFiche, colis et signatures, demandes Field Support, prêts de badges, historique des casiers et journal.\nCette action est irréversible."))return;
    if(prompt("Pour confirmer, tape le NOM de la personne :","")?.trim().toUpperCase()!==nom.toUpperCase()){showToast("Effacement annulé","err");return;}
    setBusy(true);
    try{const r=await sb.rpc("lp24_effacer_personne",{p_nom:nom,p_prenom:prenom,p_email:email});
      if(r.error)throw r.error;
      setBadges(prev=>prev.filter(b=>b.id!==editingId&&!(String(b.nom||"").trim().toUpperCase()===nom.toUpperCase()&&String(b.prenom||"").trim().toLowerCase()===prenom.toLowerCase())));
      showToast("🗑️ Toutes les données de "+prenom+" "+nom.toUpperCase()+" ont été effacées");fermer();}
    catch(e){showToast(/lp24_effacer_personne|function|fonction/i.test(String(e&&e.message))?"⚠️ Lance d'abord le script Supabase « 4-securite-rgpd.sql »":"⚠️ "+(e&&e.message||e),"err");}
    setBusy(false);};
  return el("div",{style:{display:"flex",alignItems:"center",gap:8,flexWrap:"wrap",background:"var(--surface2)",borderRadius:10,padding:"8px 12px",marginBottom:12,fontSize:12.5,color:"var(--text2)"}},
    el("span",{style:{fontWeight:700}},"🔒 Données personnelles"),el("span",{style:{flex:1}}),
    el("button",{type:"button",className:"btn btn-outline",disabled:busy,style:{fontSize:12,padding:"4px 10px"},onClick:exporter},"📄 Exporter ses données"),
    admin&&el("button",{type:"button",className:"btn btn-outline",disabled:busy,style:{fontSize:12,padding:"4px 10px",color:"#DC2626",borderColor:"#FCA5A5"},onClick:effacer},"🗑️ Tout effacer"));
}
'''
s=s.replace('function SettingsModal(',COMP+'\nfunction SettingsModal(')
# mot de passe : 8 caractères minimum
rep('if(pwd.length<6){fail("Le mot de passe doit faire au moins 6 caractères.");return;}','if(pwd.length<8){fail("Le mot de passe doit faire au moins 8 caractères.");return;}')
# Workday : on réduit la copie à l'import…
rep('parsed.forEach(p=>{next[p.matricule]=p;});\n        // ── FIX: Persister wdCache dans Supabase (id:2) — IIFE async car setWdCache callback non-async ──\n        (async()=>{try{if(sb)await sb.from("lp24_settings").upsert({id:2,data:JSON.stringify(next)});}catch(e){}})();\n        return next;});',
    'parsed.forEach(p=>{next[p.matricule]=p;});\n        const mini=wdMinimiser(next,window._badgesWd||[]);\n        (async()=>{try{if(sb)await sb.from("lp24_settings").upsert({id:2,data:JSON.stringify(mini)});}catch(e){}})();\n        return mini;});')
# … et on nettoie l'existant (une fois les fiches chargées, compte administrateur)
rep('  const navActif=id=>','''  useEffect(()=>{window._badgesWd=badges;window._estAdmin=!!(session&&session.role==="admin");},[badges,session]);
  useEffect(()=>{if(!wdCache||!badges||badges.length<1||!session||session.role!=="admin")return;
    const m=wdMinimiser(wdCache,badges);if(Object.keys(m).length<Object.keys(wdCache).length){setWdCache(m);
      (async()=>{try{if(sb)await sb.from("lp24_settings").upsert({id:2,data:JSON.stringify(m)});}catch(e){}})();}},[wdCache,badges.length,session&&session.role]);
  const navActif=id=>''')
# fiche : export / effacement
rep('''        React.createElement("div",{style:{display:"flex",alignItems:"center",gap:8,marginBottom:10}},
          wdCache&&Object.keys(wdCache).length>0?''','''        editing&&React.createElement(DonneesPersonne,{fiche:form,showToast,setBadges,editingId:editing,fermer:()=>{setShowForm(false);setEditing(null);}}),
        React.createElement("div",{style:{display:"flex",alignItems:"center",gap:8,marginBottom:10}},
          wdCache&&Object.keys(wdCache).length>0?''')
# Aide : information RGPD
rep('''  {id:"_reglages",t:"⚙️ Réglages (roue dentée)"''','''  {id:"_rgpd",t:"🔒 Données personnelles (RGPD)",l:["Ce qui est enregistré : nom, prénom, matricule, e-mail professionnel, manager, n° de badge et de casier, dates d'entrée et de départ ; pour les colis et les badges de prêt, le nom, l'e-mail, les dates et la signature à la remise. Aucune adresse personnelle, date de naissance, donnée de santé ni salaire.",
    "Pourquoi : gestion de l'accueil du site (badges, casiers, colis, arrivées et départs), sur la base de l'intérêt légitime de l'entreprise.",
    "Qui y a accès : uniquement les comptes de l'appli, ajoutés par l'administrateur. La base est fermée à toute personne non connectée.",
    "Combien de temps : tout ce qui concerne une personne partie (fiche archivée, colis remis, prêts, journaux) est effacé automatiquement 24 mois après. La copie Workday ne garde que les personnes du site et les arrivées récentes.",
    "Droits des personnes : dans la fiche, « 📄 Exporter ses données » produit le fichier de toutes ses données (droit d'accès) ; « 🗑️ Tout effacer » les supprime définitivement (droit à l'effacement, administrateur).",
    "Prestataires : Supabase (base de données), EmailJS (envoi des mails), GitHub (hébergement de la page). À inscrire au registre des traitements de l'entreprise."]},
  {id:"_reglages",t:"⚙️ Réglages (roue dentée)"''')
rep('const secs=AIDE_SECTIONS.filter(x=>x.id==="_reglages"?peutReglages:(!canAccess||canAccess(x.id)));','const secs=AIDE_SECTIONS.filter(x=>x.id==="_rgpd"?true:x.id==="_reglages"?peutReglages:(!canAccess||canAccess(x.id)));')
open(p,'w').write(s)
