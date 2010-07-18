/* @(#)djbmx.c
 * Author: Sebastien Tanguy <seb+scripts@death-gate.fr.eu.org>
 * Version: $Id$
 */

/*
 * You can redistribute and/or modify this software under the terms of
 * the GNU General Public License v2.
 */

/*
*** Call Tree:
 * main 
 *   mx_list_init 
 *   mx_list_fill
 *     mx_list_fill_name
 *       mx_list_add_ip
 *   mx_list_test_them
 *     sw_init
 *       _create_socket
 *     sw_select
 *   mx_list_clear
***
 */

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>


#include <dns.h>
#include <djbdns/uint16.h>

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <glib.h>

void st_resolve( const char* );

typedef unsigned char uchar_t;

typedef struct 
{
    GList* mxs;
    int mx_ok;
    int mx_total;
} mx_list_t;

void mx_list_init( mx_list_t* );
void mx_list_fill( mx_list_t*, const char* );
void mx_list_fill_name( mx_list_t* , const char* );
void mx_list_add_ip( mx_list_t* , const char* );
void mx_list_test_them( mx_list_t* );
void mx_list_clear( mx_list_t* );

uchar_t mx_debug_mode = 0;

int main( int argc, char* argv [] )
{
    mx_list_t mx_list;

    if ( argc != 2 ) {
        fprintf( stderr, "Wrong number of arguments.\n" );
        fprintf( stderr, "Usage:\n" );
        fprintf( stderr, "\t%s {domainname}\n", argv[ 0 ] );
        return -1;
    }
    
    mx_list_init( &mx_list );

    // look up DNS records
    mx_list_fill( &mx_list, argv[ 1 ] );
    // now, try those servers
    mx_list_test_them( &mx_list );
    
    printf( "Total MX : %d\n", mx_list.mx_total );
    printf( "MX up    : %d\n", mx_list.mx_ok );
    
    mx_list_clear( &mx_list );
    return 0;
}


void mx_list_init( mx_list_t* ml )
{
    ml->mxs = 0L;
    ml->mx_ok = 0;
    ml->mx_total = 0;
}

void mx_list_fill( mx_list_t* ml, const char* domain )
{
    stralloc mxs = { 0 };
    stralloc host = { 0 };
    char* current;

    // create the "djb-string" and look up the MX servers
    stralloc_copys( &host, domain );
    if ( 0 != dns_mx( &mxs, &host ) ) {
        fprintf( stderr, "Error resolving\n" );
        exit( -1 );
    }

    // now, for each MX, we resolve the hostname
    current = mxs.s;
    while ( current < ( mxs.s + mxs.len ) ) {
        int weight = 255 * current[ 0 ] + current[ 1 ];
        current += 2;
        if ( mx_debug_mode )
            fprintf( stdout,
                     "%s\t\tMX\t%-2d\t%s\n",
                     domain,
                     weight,
                     current );
        // we have one hostname, look that up
        mx_list_fill_name( ml, current );
        while ( *current != 0 )
            current++;
        current++;
    }
}

void mx_list_fill_name( mx_list_t* ml, const char* host )
{
    stralloc out = {0};
    stralloc shost = {0};
    static char ip[ 16 ]; // 16 => xxx.xxx.xxx.xxx\0
    uchar_t* xtra;
    int i;
    
    stralloc_copys( &shost, host );

    // do the lookup
    dns_ip4( &out, &shost );

    // for each entry, rebuild the IP address
    i = 0;
    xtra = (uchar_t*)out.s;
    while ( i  < out.len ) {
        snprintf( ip, 16, "%d.%d.%d.%d",
                  (uint16)  xtra[i],
                  (uint16)  xtra[i+1],
                  (uint16)  xtra[i+2],
                  (uint16)  xtra[i+3] );
        // and add it to the list
        mx_list_add_ip( ml, ip );
        i += 4;
    }
}

int compare_in_addr( const void* lhs_, const void* rhs_ )
{
    const struct in_addr* lhs = (const struct in_addr*)lhs_;
    const struct in_addr* rhs = (const struct in_addr*)rhs_;
    if ( lhs->s_addr == rhs->s_addr ) {
        return 0;
    }
    return 1;
}
    

void mx_list_add_ip( mx_list_t* ml, const char* ip )
{
    struct in_addr* in = malloc( sizeof( struct in_addr ) );
    if ( 0 != inet_aton( ip, in ) ) {
        if ( ! g_list_find_custom( ml->mxs, in, compare_in_addr ) ) {
            ml->mxs = g_list_prepend( ml->mxs, in );
            ml->mx_total++;
        } else {
            free( in );
        }
    }
}


int _create_socket( gpointer* );


typedef struct {
    int max_socket;
    int nb_sockets;
    fd_set readset;
    int waiting_sockets;
    int* socket_list;
} socket_work ;


void sw_init( socket_work* , mx_list_t* );
int sw_select( socket_work* );

void mx_list_test_them( mx_list_t* ml )
{
    int i;
    socket_work sw;
    sw.max_socket = -1;
    sw.waiting_sockets = 0;
    // keep an  array of all our sockets  so that we can  close all of
    // them if we timeout
    sw.nb_sockets = g_list_length( ml->mxs );
    sw.socket_list = malloc( sizeof( int ) * sw.nb_sockets );
    
    FD_ZERO(&sw.readset);

    sw_init( &sw, ml );
    ml->mx_ok = sw_select( &sw );

    // close (eventual) remaining sockets
    for ( i = 0 ; i < sw.nb_sockets ; ++i ) {
        if ( sw.socket_list[ i ] > 0 ) {
            close( sw.socket_list[ i ] );
        }
    }
    
    free( sw.socket_list );
}

void sw_init( socket_work* sw, mx_list_t* ml)
{
    GList* iter;
    struct sockaddr_in sin;
    sin.sin_port = htons( 25 );
    sin.sin_family = AF_INET;
    bzero(&sin.sin_zero, sizeof(sin.sin_zero));

    for ( iter = g_list_first( ml->mxs ) ;
          NULL != iter ;
          iter = g_list_next( iter ) ) {
        int cret ;
        int sock = _create_socket( iter->data );
        // at this point, we have a non-blocking socket ready to use
        
        struct in_addr* in = (struct in_addr*)(iter->data);
        sin.sin_addr.s_addr = in->s_addr;

        cret = connect( sock, (struct sockaddr*)&sin, sizeof(sin) ) ;

        if ( ( -1 == cret ) && ( EINPROGRESS == errno ) ) {
            // connection is happening in the background
            // prepare this socket for select
            FD_SET( sock, &sw->readset );
            sw->max_socket = MAX( sock, sw->max_socket );
            sw->socket_list[ sw->waiting_sockets ] = sock;
            sw->waiting_sockets++;
        } else if ( cret == 0 ) {
            // connection already successful
            ml->mx_ok++;
            close( sock );
        } else {
            // connection already failed
        }
    }

}

int sw_select( socket_work* sw )
{
    fd_set tempset;
    int mx_ok = 0;
    struct timeval ts;

    while ( sw->waiting_sockets > 0 ) {
        int res;
        // initialize the timeout, since Linux could mess with it
        ts.tv_sec = 3;
        ts.tv_usec = 0;
        // Copy readset into the temporary set
        memcpy( &tempset, &sw->readset, sizeof( sw->readset ) );
        
        res = select( sw->max_socket+1, &tempset, NULL, NULL, &ts );
        if ( res < 0 ) {
            fprintf( stderr, "Error on select()\n" );
            break;
        } else if ( res == 0 ) {
            // timeout
            break;
        } else {
            int i;
            // now, try to find which socket did wake us up
            for ( i = 0 ; i < sw->nb_sockets ; ++i ) {
                if ( FD_ISSET( sw->socket_list[ i ], &tempset ) ){
                    // this one has something to say
                    char code[4];
                    // try  to read  something (this  will  trigger an
                    // error if the socket could not connect
                    res = read( sw->socket_list[ i ], code, 3 );
                    if ( res < 0 ) {
                        // connection failed
                    } else {
                        code[3] = 0;
                        if ( mx_debug_mode )
                            printf( "Code: %s\n", code );
                        mx_ok++;
                    }
                    // anyway, we don't need this socket anymore
                    sw->waiting_sockets--;
                    sw->socket_list[ i ] = -1 ;
                    FD_CLR( sw->socket_list[ i ], &sw->readset );
                    close( i );
                }
            }
        }           
    }
    return mx_ok;
}



int _create_socket( gpointer* data )
{
    int unit;
    int flags;
    
    if ( ( unit = socket( AF_INET, SOCK_STREAM, 0 ) ) < 0 ) {
        fprintf( stderr, "Error creating socket\n" );
    }
    /* Set socket to non-blocking */
    if ((flags = fcntl( unit, F_GETFL, 0)) < 0){
        /* Handle error */
    }
    if (fcntl(unit, F_SETFL, flags | O_NONBLOCK) < 0) {
        /* Handle error */
    }
    return unit;
}

void mx_list_clear( mx_list_t* ml )
{
    GList* iter;
    for ( iter = g_list_first( ml->mxs ) ;
          NULL != iter ;
          iter = g_list_next( iter ) ) {
        free( iter->data );
    }
    g_list_free( ml->mxs );
    ml->mxs = NULL;
}
