
def x1():
    #print("running of x1\n");
    return(11)

def add(a,b):
    return(a+b)

def echo(o):
    print("calling F1.echo with " + str(o))
    return o

def cat(a,b,c):
    print(a + b + c)

class C1:
    def __init__(self):
        self.a1 = "123"

    def m1(self):
        return("456")

    def X__getattribute__(self,attr):
        #print('ga: ' + str(self) + ' attr ' + str(attr))
        try:
            return object.__getattribute__(self,attr)
        except:
            return object.__getattribute__(self,'a1')

