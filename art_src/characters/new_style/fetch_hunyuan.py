## Скачать модель с Tencent Hunyuan 3D по ссылке «Поделиться» (на телефоне кнопки скачивания нет):
##   python3 fetch_hunyuan.py "https://3d.hunyuan.tencent.com/share?shareId=..." <папка>
## Кладёт в папку model.glb (с текстурой), geometry.glb (только форма) и source.png (картинка-исходник).
import json
import os
import re
import sys
import urllib.request

url, out = sys.argv[1], sys.argv[2]
sid = re.search(r'shareId=([0-9a-f-]+)', url).group(1)
os.makedirs(out, exist_ok=True)
with urllib.request.urlopen('https://3d.hunyuan.tencent.com/api/3d/share/' + sid) as r:
    d = json.load(r)
c = json.loads(d['sharedContent'])
res = c['result'][0]['urlResult']
print('модель:', c.get('modelType'))
for name, key in (('model.glb', 'glb'), ('geometry.glb', 'geometryGlb')):
    if res.get(key):
        urllib.request.urlretrieve(res[key], os.path.join(out, name))
        print(name, os.path.getsize(os.path.join(out, name)) // 1024, 'КБ')
if c.get('imageList'):
    urllib.request.urlretrieve(c['imageList'][0], os.path.join(out, 'source.png'))
