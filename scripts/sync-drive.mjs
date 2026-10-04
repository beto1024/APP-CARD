import{createClient}from'@supabase/supabase-js'
import{createHash,createSign}from'node:crypto'

const supabaseUrl=process.env.APP_CARD_SUPABASE_URL
const serviceKey=process.env.APP_CARD_SUPABASE_SERVICE_ROLE_KEY
const credentialsRaw=process.env.APP_CARD_GOOGLE_SERVICE_ACCOUNT_JSON
if(!supabaseUrl||!serviceKey||!credentialsRaw)throw new Error('Faltan secretos APP_CARD_SUPABASE_URL, APP_CARD_SUPABASE_SERVICE_ROLE_KEY o APP_CARD_GOOGLE_SERVICE_ACCOUNT_JSON')
const credentials=JSON.parse(credentialsRaw)
const supabase=createClient(supabaseUrl,serviceKey,{auth:{persistSession:false}})
const sources=[
  {id:process.env.DRIVE_VERBS_FILE_ID||'1kLQpfcleWpQFjnh6pXsuFyvcxXaEaBgI',name:'verbos_aleman_A1_A2_B1.md',kind:'VERB'},
  {id:process.env.DRIVE_WORDS_FILE_ID||'1Dwu_po8lP97pSQd161861XtysPJS2TKK',name:'palabras_aleman.md',kind:'WORD'},
]
const b64=value=>Buffer.from(JSON.stringify(value)).toString('base64url')
async function accessToken(){const now=Math.floor(Date.now()/1000),header=b64({alg:'RS256',typ:'JWT'}),claim=b64({iss:credentials.client_email,scope:'https://www.googleapis.com/auth/drive.readonly',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600}),unsigned=`${header}.${claim}`,sign=createSign('RSA-SHA256');sign.update(unsigned);const assertion=`${unsigned}.${sign.sign(credentials.private_key,'base64url')}`;const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});if(!response.ok)throw new Error(`Google OAuth: ${response.status}`);return(await response.json()).access_token}
async function driveFile(token,id){const headers={authorization:`Bearer ${token}`};const metaResponse=await fetch(`https://www.googleapis.com/drive/v3/files/${id}?fields=id,name,mimeType,modifiedTime,version`,{headers});if(!metaResponse.ok)throw new Error(`Drive metadata ${id}: ${metaResponse.status}`);const contentResponse=await fetch(`https://www.googleapis.com/drive/v3/files/${id}?alt=media`,{headers});if(!contentResponse.ok)throw new Error(`Drive download ${id}: ${contentResponse.status}`);return{meta:await metaResponse.json(),content:await contentResponse.text()}}
const clean=value=>value.trim().replace(/^\*+|\*+$/g,'').trim()
const slug=value=>value.normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')
const hash=value=>createHash('sha256').update(value).digest('hex')
function rows(markdown){const lines=markdown.split(/\r?\n/),result=[];let section='';for(let i=0;i<lines.length;i++){const heading=lines[i].match(/^##\s+(.+)$/);if(heading){section=clean(heading[1]);continue}if(!lines[i].trim().startsWith('|'))continue;const cells=lines[i].trim().slice(1,-1).split('|').map(clean);const next=(lines[i+1]||'').trim();if(next.startsWith('|')&&/^\|?[\s:|-]+\|?$/.test(next)){const headers=cells;i+=2;while(i<lines.length&&lines[i].trim().startsWith('|')){const values=lines[i].trim().slice(1,-1).split('|').map(clean);if(values.length===headers.length)result.push({section,headers,values});i++}i--}}return result}
function parseVerbs(markdown){return rows(markdown).filter(r=>['A1','A2','B1'].includes(r.section)&&r.headers[0]==='Español'&&r.values.length===8).map(r=>{const[german,spanish]=[r.values[1],r.values[0]],conjugations={ich:r.values[2],du:r.values[3],er_sie_es:r.values[4],wir:r.values[5],ihr:r.values[6],sie_Sie:r.values[7]},source_key=`verb:${r.section}:${slug(german)}`;return{source_key,level:r.section,part_of_speech:'Verbo',german,spanish,conjugations,content_hash:hash(JSON.stringify({german,spanish,conjugations}))}})}
function parseWords(markdown){return rows(markdown).filter(r=>r.headers[0]==='Categoría'&&r.headers[1]==='En alemán'&&r.values.length===3).map(r=>{const part_of_speech=r.values[0],german=r.values[1],spanish=r.values[2],source_key=`word:${slug(part_of_speech)}:${slug(german)}`;return{source_key,level:null,part_of_speech,german,spanish,conjugations:null,content_hash:hash(JSON.stringify({part_of_speech,german,spanish}))}})}
const token=await accessToken(),summary=[]
for(const source of sources){const{meta,content}=await driveFile(token,source.id),cards=source.kind==='VERB'?parseVerbs(content):parseWords(content);if(cards.length===0)throw new Error(`${source.name}: ninguna tarjeta válida; importación cancelada`);const{data,error}=await supabase.rpc('import_source_cards',{source_drive_id:source.id,source_name:source.name,source_kind:source.kind,source_modified_at:meta.modifiedTime,source_hash:hash(content),imported_cards:cards});if(error)throw error;summary.push({file:source.name,cards:data,modifiedTime:meta.modifiedTime})}
console.log(JSON.stringify({ok:true,summary},null,2))
