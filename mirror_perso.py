#!/usr/bin/env python
# mirror_perso.py 
# $Id$
# Copyright (c) 1998-2002 Sebastien Tanguy 
#
# Ce programme est un logiciel libre ; vous pouvez le modifier et/ou
# le redistribuer sous les termes de la GNU GPL v2+ Ce programme est
# livré sans aucune garantie.


from ftplib import FTP
from string import split
import getopt,sys,ftplib,os,time,stat
import exceptions, re

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
    def __init__(self,hote,debug,dry_run = 0):
        FTP.__init__(self,hote)
        self.set_debuglevel(debug)
        netrc = ftplib.Netrc()
        uid,passwd,acct = netrc.get_account(hote)
        self.login(uid,passwd,acct)
        self.setSymlinks()
        self._paths = [ "/" ]
        self._use_regexp = 0

        self._dry_run = dry_run
        
    def setSymlinks( self, follow = 0 ):
        self.follow_symlinks = follow

    def setRegexp( self, regexp ):
        self._use_regexp = 1
        self._regexp = re.compile( regexp )

    def debug( self, text ):
        if self.debugging:
            print text
        else:
            pass

    def __mets_a_jour(self,fich):
        self.debug( "Sending %s" % fich )
        try:
            self.storbinary("STOR "
                            + fich,open(fich,'r'),1024)
        except ftplib.error_perm:
            self.debug( "Error while sending %s " % fich )

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
#        print self._paths[-1] + filename
        if (filename[0] == '.'):
            self.debug( "Skipped %s: not following hidden files/directorties"
                        % filename )
            return
        elif self._use_regexp and self._regexp.match(
            self._paths[-1] + filename ):
            self.debug( "Regexp matched %s, skipping it" % filename )

        if stat.S_ISLNK( sf[ stat.ST_MODE ] ):
            if self.follow_symlinks:
                try:
                    sf = os.stat( filename )
                except OSError:
                    self.debug( "%s doesn't point to anything?" % filename )
                    return
            else:
                return

        if stat.S_ISDIR( sf[ stat.ST_MODE ] ):
            self.debug( "%s is a directory" % filename )
            self.parcours_dir( filename )
        elif stat.S_ISREG( sf[ stat.ST_MODE ] ):
            self.debug( "%s is a regular file" % filename )
            self.__verifie(filename)
        else:
            self.debug( "We don't know how to handle %s" % filename )

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
                self.debug( "Removing %s" % x )
                self.supprime(x)

    def parcours_dir(self,dir):
        self.debug( "+++ cd %s" % dir )
        self._paths.append( self._paths[-1] + dir + "/" )

#        print self._paths[-1]
        if self._use_regexp and self._regexp.match( self._paths[-1] ):
            self.debug( "Regexp matched %s, skipping it" % dir )
            self._paths.pop()
            return
        
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
            self.debug( "+++ cdup : %s" % self.pwd() )
        self._paths.pop()

    def supprime_fichier(self,fich):
        try:
            self.delete(fich)
        except ftplib.error_perm,msg:
            self.debug( "Error removing %s" % fich )
        return

    def supprime(self,cible):
        try:
            self.cwd(cible)
        except ftplib.error_perm,msg:
            self.debug( "Removing %s" % cible )
            self.supprime_fichier(cible)
        else:
            self.debug( "Cleaning up %s" % cible )
            # on a réussi à se placer dans le rép à supprimer
            self.clean()
            self.voidcmd("CDUP")
            self.rmd( cible )

    def clean(self):
        try:
            lst = self.nlst()
        except ftplib.error_perm,msg:
            return
        for fich in lst:
            self.supprime(fich)
        return

    def rmd( self, target ):
        if not self._dry_run:
            FTP.rmd( self, target )

    def delete( self, target ):
        if not self._dry_run:
            FTP.delete( self, target )
        
    def __del__(self):
        self.debug( "Closing ftp" )
#       self.quit()
#       ftp.close()


# fin de Mirroir


def erreur_args(s):
    print s
    print """Usage:
%s {-h host}
     [ -d ]
     [ -f local_dir ]
     [ -r remote_dir ]
     [ -e regexp ]
     [ -c ]
     [ -s ]
     [ -p ]
     [ -n ] 

  -h host : FTP server hostname
  -f local_dir : path to the local directory (defaults to: ~/public_html)
  -r remote_dir : path to the remote directory (defaults to none)
  -e regexp : exclude files or directories matching regexp
  -c : clean remote directory (dangerous!)
  -s : follow symlinks (defaults to: no)
  -p : passive FTP mode (defaults to: no)
  -n : no action, dry run mode """ % os.path.basename( sys.argv[ 0 ] )
    sys.exit(1)

def lmain():
    opts, args = getopt.getopt(sys.argv[1:],'cde:f:h:npr:s')
    
    dlevel = 0
    dry = 0
    host = ''
    orig = ''
    remote = ''
    clean = 0
    follow_symlinks = 0
    passive_mode = 0
    regexp = ''
    
    for t in opts:
        # option de debug
        if t[0] == '-d':
            dlevel = dlevel +1
        # -h <hostname>  nom du serveur
        elif t[0] == '-h':
            if host != '':
                erreur_args("Only one host at a time")
            host = t[1]
        # -f <dir_html>  répertoire d'origine des fichiers
        elif t[0] == '-f':
            if orig != '':
                erreur_args("Only one source repository at a time")
            orig = t[1]
        # suppression des fichiers distants
        elif t[0] == "-c":
            clean = 1
        # -r <dir_distant> répertoire où se placer sur le serveur
        elif t[0] == "-r":
            if remote != '':
                erreur_args("Only one remote directory")
	    remote = t[1]
        elif t[0] == "-s":
            follow_symlinks = 1
        elif t[0] == "-p":
            passive_mode = 1
        elif t[0] == "-e":
            regexp = t[1]
        elif t[0] == "-n":
            dry = 1
	else:
	    erreur_args("Unknown option : %s" % t[0])


    if orig == '':
	orig = os.environ['HOME']+"/public_html"
	
    if host == '':
	erreur_args( "No host specified" )

    os.chdir(orig)

    if dlevel:
	print host
	
    mirroir = Mirroir( host, dlevel, dry )
    mirroir.set_pasv( passive_mode )
    if regexp != '':
        mirroir.setRegexp( regexp )
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
