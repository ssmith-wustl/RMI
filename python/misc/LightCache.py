
import weakref
import pprint;
pp = pprint.PrettyPrinter(indent=0,width=10000000)

class LightCache(object):
    def __init__(self):
        self.proxy_for_object_id = {}
        self.object_id_for_proxy_id = {}
    
    def _cleanup(self,proxy):
        proxy_id = self.id_proxy(proxy)
        object_id = self.object_id_for_proxy_id[proxy_id]
        print("cleaning up after proxy " + proxy_id + " which pointed to object " + object_id)
        del self.proxy_for_object_id[object_id]
        del self.object_id_for_proxy_id[proxy_id]

    def add_if_missing(self,obj):
        obj_id = self.id_obj(obj)
        proxy = None
        try:
            proxy = self.proxy_for_object_id[obj_id]
        except:
            callback = getattr(self,'_cleanup')
            proxy = weakref.ref(obj,callback)
            proxy_id = self.id_proxy(proxy)
            self.proxy_for_object_id[obj_id] = proxy
            self.object_id_for_proxy_id[proxy_id] = obj_id
        return(proxy)

    def id_proxy(self,proxy):
        proxy_id = str(proxy)
        proxy_id = proxy_id[0:proxy_id.index(';')]
        return(proxy_id)

    def id_obj(self,obj):
        return(str(obj))

class C1(object):
    def __init__(self):
        pass

o = None
c = LightCache()
print(pp.pformat([c,c.proxy_for_object_id,c.object_id_for_proxy_id]))

o = C1()
c.add_if_missing(o)
print(pp.pformat([o,c,c.proxy_for_object_id,c.object_id_for_proxy_id]))

o = None
print(pp.pformat([o,c,c.proxy_for_object_id,c.object_id_for_proxy_id]))

if 0:
    cache = {}
    proxymap = {}

    def id_proxy(proxy):
        proxy_id = str(proxy)
        proxy_id = proxy_id[0:proxy_id.index(';')]
        return(proxy_id)

    def cleanup(proxy):
        proxy_id = id_proxy(proxy)
        obj_id = proxymap[proxy_id]
        proxymap.__delitem__(proxy_id)
        cache.__delitem__(obj_id)

    proxy = weakref.ref(o,cleanup)
    proxy_id = id_proxy(proxy)
    obj_id = str(o)

    cache[obj_id] = proxy
    proxymap[proxy_id] = obj_id
    print(RMI.pp.pformat([proxy,o,cache,proxymap]));

    o = None
    print(RMI.pp.pformat([proxy,o,cache,proxymap]));

