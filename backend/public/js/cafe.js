const state = {data:null,user:null,busy:false,bookingStation:null,closingId:null,previewSerial:0,clockOffset:0,dataSerial:0};
const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const money = value => Number(value || 0).toLocaleString('th-TH',{minimumFractionDigits:2,maximumFractionDigits:2})+' บาท';
const label = value => ({reserved:'รอเริ่มเล่น',active:'กำลังเล่น',completed:'จบการใช้งาน',cancelled:'ยกเลิก',expired:'หมดเวลาจอง'}[value] || value);
async function api(path,opt={}) {
 const headers={'Accept':'application/json','Content-Type':'application/json',...(opt.headers||{})};
 headers['X-CSRF-TOKEN']=document.querySelector('meta[name=csrf-token]')?.content || '';
 const response=await fetch('/web-api'+path,{...opt,headers});let body={};
 try {body=await response.json();} catch {throw Error('เซิร์ฟเวอร์ตอบกลับผิดรูปแบบ กรุณารีเฟรชหน้า');}
 if(!response.ok){const error=Error(Object.values(body.errors||{})[0]?.[0]||body.message||'เกิดข้อผิดพลาด');error.status=response.status;throw error;}
 return body;
}
function toast(message){$('toast').innerHTML='<div class="toast" role="status"><span>'+esc(message)+'</span><button class="icon" aria-label="ปิดข้อความ" onclick="this.parentElement.remove()">×</button></div>';}
function dialogsOpen(){return !!document.querySelector('dialog[open]');}
function busy(value){state.busy=value;document.querySelectorAll('button').forEach(b=>b.disabled=value);}
async function loadData(silent=false){
 const serial=++state.dataSerial;
 try {const data=await api('/data');if(serial!==state.dataSerial)return;state.data=data;state.user=state.data.user;state.clockOffset=new Date(state.data.server_time).getTime()-Date.now();$('who').textContent=state.user.name+' · '+(state.user.role==='admin'?'ผู้ดูแล':'สมาชิก');render();}
 catch(e){if(!silent)toast(e.message);if(e.status===401||e.status===419)location='/login';}
}
async function mutate(path,body={},method='POST'){
 if(state.busy)return;state.dataSerial++;busy(true);
 try {const result=await api(path,{method,body:JSON.stringify(body)});toast(result.message||'บันทึกแล้ว');await loadData();return result;}
 catch(e){toast(e.message);return null;}finally{busy(false);}
}
function render(){
 const d=state.data,u=state.user,admin=u.role==='admin',selected=$('zone-filter').value;
 if($('hero-kind'))$('hero-kind').textContent=admin?'CONTROL ROOM':'MEMBER PASS';
 if($('hero-title'))$('hero-title').textContent=admin?'จัดการร้านให้เห็นภาพในหน้าเดียว':'เลือกเวลาเล่นและจัดการรายการของคุณ';
 if($('hero-copy'))$('hero-copy').textContent=admin?'รับเงิน เปิดเวลา และคืนส่วนต่างจากข้อมูลชุดเดียวกัน':'เลือกเครื่อง ดูยอดเงิน และจบการใช้งานได้ด้วยตัวเอง';
 const zones=[...new Set(d.stations.map(s=>s.zone_name))];
 $('zone-filter').innerHTML='<option value="">ทุกโซน</option>'+zones.map(z=>'<option>'+esc(z)+'</option>').join('');$('zone-filter').value=selected;
 const stats=admin?[['รายได้วันนี้',money(d.stats.revenue_today)],['จบรายการวันนี้',d.stats.completed_today+' รายการ'],['เครื่องว่าง',d.stats.available+' เครื่อง'],['รอคืนเงิน',(d.refunds||[]).length+' รายการ']]:[['เครื่องทั้งหมด',d.stations.length+' เครื่อง'],['เครื่องว่าง',d.stations.filter(s=>s.status==='available').length+' เครื่อง'],['รายการของฉัน',d.open_sessions.length+' รายการ'],['ฟรีที่ใช้ได้',Math.floor(d.rewards.free_minutes_available/60)+' ชม.']];
 $('stats').innerHTML=stats.map(v=>'<div class="stat"><span class="label">'+v[0]+'</span><strong>'+v[1]+'</strong></div>').join('');
 $('stations').innerHTML=d.stations.filter(s=>!selected||s.zone_name===selected).map(s=>{
  const st={available:['ว่าง','#4ade80'],reserved:['ติดจอง','#fbbf24'],in_use:['กำลังเล่น','#fb7185'],maintenance:['ปิดปรับปรุง','#94a3b8']}[s.status];
  const open=d.open_sessions.find(x=>x.station_id===s.id);
  let actions=s.status==='available'?'<button class="primary" onclick="book('+s.id+')">'+(admin?'จองให้สมาชิก':'จองเครื่อง')+'</button>':'';
  if(admin&&s.status==='reserved'&&open)actions+='<button class="primary" onclick="start('+open.id+')">รับเงิน / เริ่มเล่น</button>';
  if(admin&&['available','maintenance'].includes(s.status)&&!open)actions+='<button class="ghost" onclick="setStatus('+s.id+',\''+(s.status==='available'?'maintenance':'available')+'\')">'+(s.status==='available'?'ปิดซ่อม':'เปิดใช้งาน')+'</button>';
  return '<article class="station" style="--accent:'+st[1]+'"><span class="badge">'+st[0]+'</span><h3>'+esc(s.station_code)+'</h3><div class="zone">'+esc(s.zone_name)+'</div><div class="specs">'+esc(s.specs_info||'ยังไม่มีรายละเอียด')+'</div><div class="price">'+money(s.package.hourly_rate)+'/ชั่วโมง</div><div class="actions">'+actions+'</div></article>';
 }).join('')||'<p class="empty">ไม่พบเครื่องในโซนนี้</p>';
 $('open-sessions').innerHTML=d.open_sessions.map(s=>'<article class="session"><b>'+esc(s.station?.station_code)+' · '+esc(s.session_code)+'</b><small>'+esc(s.user?.name||'ของฉัน')+' · '+label(s.status)+'</small><p class="muted">'+(s.planned_minutes? 'เลือกเล่น '+s.planned_minutes/60+' ชม. · ยอดจอง '+money(s.quoted_amount):'รายการเดิม: คิดค่าบริการหลังเล่น')+'</p>'+(s.status==='active'?'<p>รับเงินแล้ว '+money(s.prepaid_amount)+'</p><p class="timer" data-session="'+s.id+'"></p>':'<p class="muted">ติดต่อเคาน์เตอร์ภายใน 15 นาที</p>')+'<div class="actions">'+(s.status==='reserved'? (admin?'<button class="primary" onclick="start('+s.id+')">รับเงิน / เริ่มเล่น</button>':'')+'<button class="danger-btn" onclick="cancel('+s.id+')">ยกเลิกการจอง</button>':'<button class="danger-btn" onclick="finish('+s.id+')">ยกเลิก / จบการใช้งาน</button>')+'</div></article>').join('')||'<p class="empty">ยังไม่มีรายการที่กำลังเปิด</p>';
 const r=d.rewards;$('rewards').innerHTML='<div class="reward">สะสมเวลาแบบจ่ายแล้ว <b>'+Math.floor(r.paid_minutes/60)+' ชม. '+r.paid_minutes%60+' นาที</b><div class="bar"><i style="width:'+Math.min(100,r.paid_minutes%600/6)+'%"></i></div><p class="muted">สิทธิ์ฟรีคงเหลือ '+Math.floor(r.free_minutes_available/60)+' ชั่วโมง</p></div>';
 $('refunds').innerHTML=(d.refunds||[]).map(s=>'<article class="refund-card"><div><b>'+esc(s.session_code)+' · '+esc(s.station?.station_code)+'</b><p>'+esc(s.user?.name||'')+'</p><p>ชำระแล้ว '+money(s.prepaid_amount)+' · ค่าบริการจริง '+money(s.total_amount)+'</p><strong>ส่วนต่างรอคืน '+money(s.refund_amount)+'</strong><p class="muted">'+(admin?'คืนเงินให้สมาชิกก่อนกดยืนยัน':'กรุณาติดต่อเคาน์เตอร์ พร้อมแจ้งรหัสรายการนี้เพื่อรับเงินส่วนต่าง')+'</p></div>'+(admin?'<button class="primary" onclick="refund('+s.id+')">ยืนยันคืนเงินแล้ว</button>':'')+'</article>').join('')||'<p class="empty">ไม่มีเงินส่วนต่างที่รอคืน</p>';
 $('history').innerHTML=d.history.map(s=>'<tr><td>'+esc(s.session_code)+'</td><td>'+esc(s.user?.name)+'</td><td>'+esc(s.station?.station_code)+'</td><td>'+label(s.status)+'</td><td>'+s.minutes_used+' นาที'+(s.free_minutes_used?' (ฟรี '+s.free_minutes_used+')':'')+'</td><td>'+money(s.prepaid_amount)+'</td><td>'+money(s.total_amount)+'</td><td>'+money(s.refund_amount)+'<br>'+({pending:'รอคืนที่เคาน์เตอร์',paid:'คืนเงินแล้ว',none:'ไม่มีส่วนต่าง'}[s.refund_status]||'')+(Number(s.balance_due)>0?'<br>ชำระเพิ่ม '+money(s.balance_due):'')+'</td></tr>').join('')||'<tr><td colspan="8">ยังไม่มีรายการ</td></tr>';
 updateTimers();if(state.busy)busy(true);
}
function updateTimers(){
 if(!state.data)return;const now=Date.now()+state.clockOffset;
 document.querySelectorAll('[data-session]').forEach(el=>{const s=state.data.open_sessions.find(s=>s.id===Number(el.dataset.session));if(!s)return;
  const used=Math.max(0,Math.ceil((now-new Date(s.started_at).getTime())/60000));
  let text='เล่นแล้ว '+used+' นาที';
  if(s.scheduled_end_at){const seconds=Math.ceil((new Date(s.scheduled_end_at).getTime()-now)/1000);text+=seconds>0?' · เหลือ '+Math.floor(seconds/3600)+' ชม. '+Math.floor(seconds%3600/60)+' นาที':' · ครบเวลาที่จองแล้ว กรุณาจบการใช้งานเพื่อหยุดคิดค่าบริการ';}
  el.textContent=text;
 });
}
function book(id){
 if(state.busy)return;const d=state.data,admin=state.user.role==='admin';
 if(!admin&&d.open_sessions.length){toast('คุณมีรายการเดิมอยู่ กรุณายกเลิกหรือจบการใช้งานก่อนจองใหม่');return;}
 if(admin&&!d.members.length){toast('ยังไม่มีสมาชิกให้จองเครื่อง');return;}
 state.bookingStation=d.stations.find(s=>s.id===id);if(!state.bookingStation)return;
 $('booking-name').textContent=state.bookingStation.station_code+' · '+state.bookingStation.zone_name;
 $('member-label').hidden=!admin;$('member-select').innerHTML=d.members.map(m=>'<option value="'+m.id+'">'+esc(m.name)+' ('+esc(m.email)+')</option>').join('');
 $('booking-hours').value='1';updateQuote();$('booking-modal').showModal();
}
function updateQuote(){const s=state.bookingStation;if(!s)return;$('booking-quote').textContent=money(Number(s.package.hourly_rate)*Number($('booking-hours').value));}
async function submitBooking(event){
 event.preventDefault();if(state.busy||!state.bookingStation)return;
 const body={station_id:state.bookingStation.id,hours:Number($('booking-hours').value)};const admin=state.user.role==='admin';if(admin)body.user_id=Number($('member-select').value);
 const result=await mutate(admin?'/admin/bookings':'/bookings',body);if(result){$('booking-modal').close();state.bookingStation=null;}
}
async function cancel(id){if(confirm('ยกเลิกการจองนี้? ยังไม่เริ่มเล่นและไม่มีค่าบริการ'))await mutate('/sessions/'+id+'/cancel');}
async function start(id){
 const s=state.data.open_sessions.find(s=>s.id===id);if(!s||state.busy)return;
 const text=s.planned_minutes?'ยืนยันว่าได้รับเงิน '+money(s.quoted_amount)+' ที่เคาน์เตอร์แล้ว และเริ่มเล่น '+s.planned_minutes/60+' ชั่วโมง?':'เริ่มเล่นรายการเดิม? คิดค่าบริการหลังเล่น';
 if(confirm(text))await mutate('/admin/sessions/'+id+'/start',{payment_received:true});
}
async function finish(id){
 if(state.busy)return;state.closingId=id;$('use-reward').checked=false;$('settlement-modal').showModal();await updateSettlement();
}
async function updateSettlement(){
 const id=state.closingId,serial=++state.previewSerial;if(!id)return;
 $('confirm-end').disabled=true;$('settlement-bill').textContent='กำลังคำนวณ...';
 try {const result=await api('/sessions/'+id+'/settlement?use_reward='+($('use-reward').checked?1:0));if(serial!==state.previewSerial||!$('settlement-modal').open)return;
  const b=result.data;$('settlement-bill').innerHTML='<dl class="bill">'+[['ชำระไว้แล้ว',money(b.prepaid_amount)],['ใช้เวลา',b.minutes_used+' นาที'],['ใช้สิทธิ์ฟรี',b.free_minutes_used+' นาที'],['ค่าบริการจริง',money(b.total_amount)],['เงินส่วนต่างรอคืน',money(b.refund_amount)],['ยอดชำระเพิ่ม',money(b.balance_due)]].map(r=>'<div><dt>'+r[0]+'</dt><dd>'+r[1]+'</dd></div>').join('')+'</dl><p class="muted">ยอดนี้เป็นประมาณการ ระบบคำนวณอีกครั้งเมื่อยืนยันจบ คิดตามนาทีโดยปัดนาทีที่เริ่มแล้วขึ้น</p><p>เงินส่วนต่างรับคืนที่เคาน์เตอร์ ไม่มีการโอนเงินอัตโนมัติ</p>';$('confirm-end').disabled=false;
 }catch(e){if(serial===state.previewSerial)$('settlement-bill').textContent=e.message;}
}
async function submitEnd(){
 if(state.busy||!state.closingId)return;const result=await mutate('/sessions/'+state.closingId+'/end',{use_reward:$('use-reward').checked});if(result){$('settlement-modal').close();state.closingId=null;}else await updateSettlement();
}
async function refund(id){const s=state.data.refunds.find(s=>s.id===id);if(s&&confirm('ยืนยันว่าได้ส่งเงินส่วนต่าง '+money(s.refund_amount)+' คืนให้ '+s.user?.name+' แล้ว?'))await mutate('/admin/sessions/'+id+'/refund');}
async function setStatus(id,status){await mutate('/admin/stations/'+id+'/status',{status},'PATCH');}
async function logout(){if(state.busy)return;try{const r=await fetch('/logout',{method:'POST',headers:{Accept:'application/json','X-CSRF-TOKEN':document.querySelector('meta[name=csrf-token]')?.content||''}});if(!r.ok)throw Error('ออกจากระบบไม่สำเร็จ กรุณาลองใหม่');localStorage.removeItem('cafe_token');location='/login';}catch(e){toast(e.message);}}
loadData();setInterval(updateTimers,1000);setInterval(()=>{if(!state.busy&&!dialogsOpen())loadData(true);},15000);
