import json,time,base64
from pathlib import Path
from urllib.parse import urlsplit
from playwright.sync_api import sync_playwright,expect
v=dict(line.split('=',1) for line in Path('.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
host=urlsplit(v['VITE_SUPABASE_URL'].strip().strip('\"\'')).hostname
key='sb-'+host.split('.')[0]+'-auth-token'
uid='11111111-1111-4111-8111-111111111111';email='contatodavidcaua@gmail.com'
user={'id':uid,'email':email,'aud':'authenticated','role':'authenticated','app_metadata':{},'user_metadata':{}}
def session(exp):
 enc=lambda x:base64.urlsafe_b64encode(json.dumps(x).encode()).decode().rstrip('=')
 token=enc({'alg':'HS256','typ':'JWT'})+'.'+enc({'sub':uid,'email':email,'role':'authenticated','exp':exp})+'.mock'
 return {'access_token':token,'refresh_token':'mock','expires_at':exp,'expires_in':3600,'token_type':'bearer','user':user}
career={'id':'saved-career','user_id':uid,'nickname':'Existing tester','club_id':None,'status':'active'}
with sync_playwright() as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox'])
 for case in ['career401','career500','match401','refreshInvalid','refreshValid','noCareer']:
  ctx=b.new_context();page=ctx.new_page();errors=[];calls=[];state={'career500':case=='career500'}
  page.on('pageerror',lambda e:errors.append(str(e)))
  s=session(int(time.time())+(-3600 if case.startswith('refresh') else 3600))
  page.add_init_script('localStorage.setItem('+json.dumps(key)+','+json.dumps(json.dumps(s))+');localStorage.setItem("progress-sentinel","preserved")')
  def api(route):
   path=urlsplit(route.request.url).path;calls.append((route.request.method,path))
   status=200;data=[]
   if path=='/auth/v1/logout':status=204;data=None
   elif path=='/auth/v1/user':data=user
   elif path=='/auth/v1/token':
    if case=='refreshInvalid':status=400;data={'code':'refresh_token_not_found','message':'Invalid Refresh Token'}
    else:data=session(int(time.time())+3600)
   elif path=='/rest/v1/careers':
    if case=='career401':status=401;data={'code':'PGRST301','message':'JWT expired'}
    elif state['career500']:status=500;data={'code':'XX000','message':'database unavailable'}
    elif case=='noCareer':status=200;data=None
    else:data=career
   elif path=='/rest/v1/rpc/mgr_match_start':status=401;data={'code':'PGRST301','message':'JWT expired'}
   route.fulfill(status=status,content_type='application/json',body='' if status==204 else json.dumps(data))
  page.route('https://'+host+'/**',api)
  page.goto('http://127.0.0.1:5173/',wait_until='domcontentloaded')
  login=page.get_by_role('button',name='Entrar com o Google')
  if case in ['career401','refreshInvalid']:expect(login).to_be_visible()
  elif case=='noCareer':expect(page.get_by_text('Criar treinador',exact=True)).to_be_visible()
  else:
   if case=='career500':
    expect(page.get_by_role('heading',name='Não foi possível carregar sua carreira')).to_be_visible()
    assert page.get_by_text('Criar treinador',exact=True).count()==0
    state['career500']=False
    page.get_by_role('button',name='Tentar novamente',exact=True).click()
   expect(page.get_by_text('Propostas',exact=True)).to_be_visible()
   if case=='match401':
    result=page.evaluate('''async () => { const api=await import('/src/features/seasons/services/managerApi.js');try { await api.startMatch(); } catch(e) { return e.code; } }''')
    assert result=='PGRST301',result
    expect(login).to_be_visible()
    assert sum(path=='/rest/v1/rpc/mgr_match_start' for _,path in calls)==1
    assert 'JWT expired' not in page.locator('body').inner_text()
    renewed=session(int(time.time())+7200)
    page.evaluate("async (session) => { const {supabase}=await import('/src/lib/supabaseClient.js'); const {error}=await supabase.auth.setSession(session);if(error) throw error; }", {'access_token':renewed['access_token'],'refresh_token':'mock'})
    expect(page.get_by_text('Propostas',exact=True)).to_be_visible()
    assert page.get_by_text('Criar treinador',exact=True).count()==0
  assert page.evaluate('localStorage.getItem("progress-sentinel")')=='preserved'
  assert not errors,errors
  if case.startswith('refresh'):assert any(path=='/auth/v1/token' for _,path in calls)
  print('PASS',case,flush=True);ctx.close()
 b.close()
