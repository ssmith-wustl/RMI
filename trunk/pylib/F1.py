
def x1():
    #print("running of x1\n");
    return(11)

def add(a,b):
    return(a+b)

def echo(o):
    print("got for echo: " + str(o))
    return o

class C1:
    def __init__(self):
        self.a1 = "123"

    def m1(self):
        #print("method1\n")
        return("456")

    def __getattribute__(self,attr):
        #print('ga: ' + str(self) + ' attr ' + str(attr))
        try:
            return object.__getattribute__(self,attr)
        except:
            return object.__getattribute__(self,'a1')

