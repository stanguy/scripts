#!/usr/bin/env python
# mirror_perso.py 
# Copyright (c) 1998-2002 Sebastien Tanguy 
#
# Ce programme est un logiciel libre ; vous pouvez le modifier et/ou
# le redistribuer sous les termes de la GNU GPL v2+ Ce programme est
# livré sans aucune garantie.


from ftplib import FTP
from string import split
import getopt,sys,ftplib,os,time,stat
import exceptions

#on passe une chaine de date et le nom du fichier
def isolder(lt,rg):
    dtr = time.gmtime((os.stat(rg))[9])
    # année
    lv = int(lt[0:4])
    # an 2000, nous voilà
    if lv < 1950:
        # pour le reste du truc, on corrige
        lv = int(lt[2:5]) + 1900
        lt = lt[1:]
    
    if lv != dtr[0]:
	return lv < dtr[0]
    # mois
    lv = int(lt[4:6])
    if lv != dtr[1]:
	return lv < dtr[1]
    # jour
    lv = int(lt[6:8])
    if lv != dtr[2]:
	return lv < dtr[2]
    # heure
    lv = int(lt[8:10])
    if lv != dtr[3]:
	return lv < dtr[3]
    # minute
    lv = int(lt[10:12])
    if lv != dtr[4]:
	return lv < dtr[4]
    # seconde
    lv = int(lt[12:14])
    if lv != dtr[5]:
	return lv < dtr[5]
    return 0

class Mirroir (FTP):
    def __init__(self,hote,debug):
	FTP.__init__(self,hote)
	self.set_debuglevel(debug)
	netrc = ftplib.Netrc()
	uid,passwd,acct = netrc.get_account(hote)
	self.login(uid,passwd,acct)

    def setSymlinks( self, follow = 0 ):
        self.follow_symlinks = follow

    def __mets_a_jour(self,fich):
	if self.debugging:
	    print "Envoi du fichier ", fich
	try:
	    self.storbinary("STOR "
			    + fich,open(fich,'r'),1024)
	except ftplib.error_perm:
	    print "Erreur d'envoi de ", fich

    def __verifie(self,fich):
	try:
	    resp = self.sendcmd("MDTM "+fich)
	except ftplib.error_perm,v:
	    self.__mets_a_jour(fich)
	else:
	    rfcdate = split(resp)[1]
	    if isolder(rfcdate,fich):
		self.__mets_a_jour(fich)

    def __doFile( self, filename ):
        # on ne suit pas les liens ou les fichiers/réps cachés
        sf = os.lstat( filename )
        if (filename[0] == '.'):
            if self.debugging:
                print "On passe ",filename," pour racisme"
            return

        if stat.S_ISLNK( sf[ stat.ST_MODE ] ):
            if self.follow_symlinks:
                print "Woooh, un lien à suivre ! (", filename, ")"
                try:
                    sf = os.stat( filename )
                except OSError:
                    if self.debugging:
                        print filename, " Doesn't point to anything?"
                    return

        if stat.S_ISDIR( sf[ stat.ST_MODE ] ):
            if self.debugging:
                print filename," est un répertoire"
            self.parcours_dir( filename )
        elif stat.S_ISREG( sf[ stat.ST_MODE ] ):
            if self.debugging:
                print filename," est un fichier"
            self.__verifie(filename)
        else:
            print filename," pose problème *****"

    def parcours(self):
        try:
            fichiers_distants = self.nlst()
        except ftplib.error_perm,v:
            fichiers_distants =  []
        dfichiers = {}
        for x in fichiers_distants:
            dfichiers[x] = 1
	for fich in os.listdir(os.curdir):
            self.__doFile( fich )
            dfichiers[fich] = 0
        for x in dfichiers.keys():
            if dfichiers[x]:
                if self.debugging:
                    print "Destruction de ",x
                self.supprime(x)

    def parcours_dir(self,dir):
	if self.debugging:
	    print "+++ cd ",dir
	olddir= os.getcwd()
	os.chdir(dir)
	excraised = 1
	while excraised:
	    try:
		self.cwd(dir)
	    except ftplib.error_perm,msg:
		self.voidcmd("MKD "+dir)
		continue
	    else:
		excraised = 0
	    self.parcours()
	    os.chdir(olddir)
	    self.voidcmd("CDUP")
	    if self.debugging:
		print "+++ cdup : %s" % self.pwd()

    def supprime_fichier(self,fich):
	try:
	    self.delete(fich)
	except ftplib.error_perm,msg:
	    if self.debugging:
		print "Erreur pour ",fich
	return

    def supprime(self,cible):
        try:
            self.cwd(cible)
        except ftplib.error_perm,msg:
            if self.debugging:
                print "Destruction de ",cible
            self.supprime_fichier(cible)
        else:
            if self.debugging:
                print "Nettoyage de ",cible
            # on a réussi à se placer dans le rép à supprimer
            self.clean()
            self.voidcmd("CDUP")
            self.supprime_fichier(cible)

    def clean(self):
	try:
	    lst = self.nlst()
	except ftplib.error_perm,msg:
	    return
	for fich in lst:
            self.supprime(fich)
	return
	
    def __del__(self):
	if self.debugging:
	    print "Closing ftp"
#	self.quit()
#       ftp.close()


# fin de Mirroir

def erreur_args(s):
    print s
    sys.exit(1)

def lmain():
    opts, args = getopt.getopt(sys.argv[1:],'dh:f:cr:s')
    
    dlevel = 0
    host = ''
    orig = ''
    remote = ''
    clean = 0
    follow_symlinks = 0
    
    for t in opts:
        # option de debug
	if t[0] == '-d':
	    dlevel = dlevel +1
        # -h <hostname>  nom du serveur
	elif t[0] == '-h':
	    if host != '':
		erreur_args("un seul hôte à la fois, svp")
	    host = t[1]
        # -f <dir_html>  répertoire d'origine des fichiers
	elif t[0] == '-f':
	    if orig != '':
		erreur_args("une seule origine à la fois, svp")
	    orig = t[1]
        # suppression des fichiers distants
	elif t[0] == "-c":
	    clean = 1
        # -r <dir_distant> répertoire où se placer sur le serveur
	elif t[0] == "-r":
	    if remote != '':
		erreur_args("Un seul répertoire distant à la fois, merci")
	    remote = t[1]
        elif t[0] == "-s":
            follow_symlinks = 1
	else:
	    erreur_args("Argument inconnu : %s" % t[0])


    if orig == '':
	orig = os.environ['HOME']+"/public_html"
	
    if host == '':
	host = 'perso-ftp.wanadoo.fr'

    os.chdir(orig)

    if dlevel:
	print host
	
    mirroir = Mirroir(host,dlevel)
    if remote != '':
	mirroir.cwd(remote)

    if follow_symlinks:
        mirroir.setSymlinks( follow = 1 )

    if clean:
	mirroir.clean()
    else:
	mirroir.parcours()


if __name__ == '__main__':
    lmain()
