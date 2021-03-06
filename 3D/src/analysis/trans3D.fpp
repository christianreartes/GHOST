!=================================================================
      PROGRAM TRANSFER3D
!=================================================================
! TRANSFER3D code (part of the GHOST suite)
!
! Numerically computes the shell-to-shell transfers for 3 
! dimensional HD/MHD/Hall-MHD using data generated by GHOST.
! The pseudo-spectral method is used to compute spatial
! derivatives. This tool ONLY works with cubic data in
! (2.pi)^3 domains.
!
! NOTATION: index 'i' is 'x' 
!           index 'j' is 'y'
!           index 'k' is 'z'
! 
! Conditional compilation options:
!           HD_SOL   builds the hydrodynamic transfer
!           MHD_SOL  builds the MHD transfer
!           HMHD_SOL builds the Hall-MHD transfer
!           ROTH_SOL builds the HD transfer in a rotating frame
!
! 2005 Alexandros Alexakis and Pablo D. Mininni.
!      National Center for Atmospheric Research.
!
! 15 Feb 2007: Main program for all transfers
! 21 Feb 2007: POSIX and MPI/IO support
! 10 Mar 2007: FFTW-2.x and FFTW-3.x support
!=================================================================

!
! Definitions for conditional compilation

#ifdef HD_SOL
#define VORTICITY_
#endif

#ifdef MHD_SOL
#define MAGFIELD_
#define ELSASSER_
#endif

#ifdef HMHD_SOL
#define MAGFIELD_
#define HALLTERM_
#endif

#ifdef ROTH_SOL
#define VORTICITY_
#define ROTATION_
#endif 

!
! Modules

      USE fprecision
      USE commtypes
      USE mpivars
      USE filefmt
      USE iovar
      USE grid
      USE fft
      USE ali
      USE var
      USE kes
      IMPLICIT NONE

!
! Arrays for the fields and the transfers

      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: vx,vy,vz
#ifdef VORTICITY_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: wx,wy,wz
#endif 
#ifdef MAGFIELD_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: bx,by,bz
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: C1,C2,C3
#endif 
#ifdef ELSASSER_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: px,py,pz
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: mx,my,mz
#endif 
#ifdef HALLTERM_
      COMPLEX(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:) :: jx,jy,jz
#endif 

      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:)    :: rvx,rvy,rvz
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)      :: uu,hh
#ifdef MAGFIELD_
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:)    :: rbx,rby,rbz
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)      :: ub,bu,bb
#endif 
#ifdef ELSASSER_
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:)    :: rpx,rpy,rpz
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:)    :: rmx,rmy,rmz
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)      :: pp,mm
#endif 
#ifdef HALLTERM_
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:,:)    :: rjx,rjy,rjz
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)      :: jb,jj
#endif 
#ifdef ROTATION_
      REAL(KIND=GP), ALLOCATABLE, DIMENSION (:,:)      :: para,perp
#endif

!
! Auxiliary variables

      REAL(KIND=GP)    :: tmp

      INTEGER :: n
      INTEGER :: stat
      INTEGER :: cold
      INTEGER :: kini
      INTEGER :: ktrn
      INTEGER :: heli
      INTEGER :: i,j,k
      INTEGER :: kk,kq
#ifdef ELSASSER_
      INTEGER :: elsa
#endif

      TYPE(IOPLAN) :: planio

      CHARACTER(len=100) :: odir,idir

!
! Verifies proper compilation of the tool

      IF ( (nx.ne.ny).or.(ny.ne.nz) ) THEN
        IF (myrank.eq.0) &
           PRINT *,'This tool only works with cubic data in (2.pi)^3 domains'
        STOP
      ENDIF
      n = nx

!
! Initializes the MPI and I/O libraries

      CALL MPI_INIT(ierr)
      CALL MPI_COMM_SIZE(MPI_COMM_WORLD,nprocs,ierr)
      CALL MPI_COMM_RANK(MPI_COMM_WORLD,myrank,ierr)
      CALL range(1,n/2+1,nprocs,myrank,ista,iend)
      CALL range(1,n,nprocs,myrank,ksta,kend)
      CALL io_init(myrank,(/n,n,n/),ksta,kend,planio)

!
! Initializes the FFT library
! Use FFTW_ESTIMATE in short runs and FFTW_MEASURE 
! in long runs

      CALL fftp3d_create_plan(planrc,(/n,n,n/),FFTW_REAL_TO_COMPLEX, &
          FFTW_MEASURE)
      CALL fftp3d_create_plan(plancr,(/n,n,n/),FFTW_COMPLEX_TO_REAL, &
          FFTW_MEASURE)

!
! Allocates memory for distributed blocks

      ALLOCATE( vx(n,n,ista:iend) )
      ALLOCATE( vy(n,n,ista:iend) )
      ALLOCATE( vz(n,n,ista:iend) )
#ifdef MAGFIELD_
      ALLOCATE( bx(n,n,ista:iend) )
      ALLOCATE( by(n,n,ista:iend) )
      ALLOCATE( bz(n,n,ista:iend) )
      ALLOCATE( C1(n,n,ista:iend) )
      ALLOCATE( C2(n,n,ista:iend) )
      ALLOCATE( C3(n,n,ista:iend) )
#endif 
#ifdef ELSASSER_
      ALLOCATE( px(n,n,ista:iend) )
      ALLOCATE( py(n,n,ista:iend) )
      ALLOCATE( pz(n,n,ista:iend) )
      ALLOCATE( mx(n,n,ista:iend) )
      ALLOCATE( my(n,n,ista:iend) )
      ALLOCATE( mz(n,n,ista:iend) )
#endif 
#ifdef HALLTERM_
      ALLOCATE( jx(n,n,ista:iend) )
      ALLOCATE( jy(n,n,ista:iend) )
      ALLOCATE( jz(n,n,ista:iend) )
#endif 
      ALLOCATE( kx(n), ky(n), kz(n) )
      ALLOCATE( kn2(n,n,ista:iend), kk2(n,n,ista:iend) )
      ALLOCATE( rvx(n,n,ksta:kend) )
      ALLOCATE( rvy(n,n,ksta:kend) )
      ALLOCATE( rvz(n,n,ksta:kend) )
#ifdef MAGFIELD_
      ALLOCATE( rbx(n,n,ksta:kend) )
      ALLOCATE( rby(n,n,ksta:kend) )
      ALLOCATE( rbz(n,n,ksta:kend) )
#endif 
#ifdef HALLTERM_
      ALLOCATE( rjx(n,n,ksta:kend) )
      ALLOCATE( rjy(n,n,ksta:kend) )
      ALLOCATE( rjz(n,n,ksta:kend) )
#endif 

!
! Some constants for the FFT
!     kmax: maximum truncation for dealiasing
!     tiny: minimum truncation for dealiasing

      kmax = (REAL(n,KIND=GP)/3.)**2
      tiny = 1e-5

!
! Builds the wave number and the square wave 
! number matrixes

      DO i = 1,n/2
         kx(i) = real(i-1,kind=GP)
         kx(i+n/2) = real(i-n/2-1,kind=GP)
      END DO
      ky = kx
      kz = kx
      DO i = ista,iend
         DO j = 1,n
            DO k = 1,n
               kk2(k,j,i) = kx(i)**2+ky(j)**2+kz(k)**2
            END DO
         END DO
      END DO
      kn2 = kk2

!
! Reads from the external file 'transfer.txt' the 
! parameters that will be used to compute the transfer
!     idir : directory for unformatted input (field components)
!     odir : directory for unformatted output (transfers)
!     stat : number of the file to analyze
!     cold : =0 restart a previous computation
!            =1 start a new computation
!     ktrn : maximum k used to compute the transfer
!     heli : =0 skips transfer of helicity
!            =1 computes the transfer of helicity
!     elsa : =0 skips transfer of Elsasser variables (MHD_SOL)
!            =1 computes transfer of Elsasser variables (MHD_SOL)

      IF (myrank.eq.0) THEN
         OPEN(1,file='transfer.txt',status='unknown')
         READ(1,'(a100)') idir
         READ(1,'(a100)') odir
         READ(1,*) stat
         READ(1,*) cold
         READ(1,*) ktrn
         READ(1,*) heli
#ifdef ELSASSER_
         READ(1,*) elsa
#endif
         CLOSE(1)
      ENDIF
      CALL MPI_BCAST(idir,100,MPI_CHARACTER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(odir,100,MPI_CHARACTER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(stat,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(ktrn,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
      CALL MPI_BCAST(heli,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
#ifdef ELSASSER_
      CALL MPI_BCAST(elsa,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)
#endif

!
! Reads the external binary files with the 
! fields components.

      WRITE(ext, fmtext) stat
      CALL io_read(1,idir,'vx',ext,planio,rvx)
      CALL io_read(1,idir,'vy',ext,planio,rvy)
      CALL io_read(1,idir,'vz',ext,planio,rvz)
      CALL fftp3d_real_to_complex(planrc,rvx,vx,MPI_COMM_WORLD)
      CALL fftp3d_real_to_complex(planrc,rvy,vy,MPI_COMM_WORLD)
      CALL fftp3d_real_to_complex(planrc,rvz,vz,MPI_COMM_WORLD)
#ifdef MAGFIELD_
      CALL io_read(1,idir,'ax',ext,planio,rbx)
      CALL io_read(1,idir,'ay',ext,planio,rby)
      CALL io_read(1,idir,'az',ext,planio,rbz)
      CALL fftp3d_real_to_complex(planrc,rbx,C1,MPI_COMM_WORLD)
      CALL fftp3d_real_to_complex(planrc,rby,C2,MPI_COMM_WORLD)
      CALL fftp3d_real_to_complex(planrc,rbz,C3,MPI_COMM_WORLD)
      CALL rotor3(C2,C3,bx,1)           ! magnetic field
      CALL rotor3(C1,C3,by,2)
      CALL rotor3(C1,C2,bz,3)
#endif
#ifdef HALLTERM_
      CALL laplak3(C1,jx)               ! minus the current density
      CALL laplak3(C2,jy)
      CALL laplak3(C3,jz)
#endif
#ifdef MAGFIELD_
      tmp = 1./REAL(n,KIND=GP)**3
      DO i = ista,iend
         DO j = 1,n
            DO k = 1,n
               C1(k,j,i) = bx(k,j,i)*tmp
               C2(k,j,i) = by(k,j,i)*tmp
               C3(k,j,i) = bz(k,j,i)*tmp
            END DO
         END DO
      END DO
      CALL fftp3d_complex_to_real(plancr,C1,rbx,MPI_COMM_WORLD)
      CALL fftp3d_complex_to_real(plancr,C2,rby,MPI_COMM_WORLD)
      CALL fftp3d_complex_to_real(plancr,C3,rbz,MPI_COMM_WORLD)
#endif
#ifdef HALLTERM_
      DO i = ista,iend
         DO j = 1,n
            DO k = 1,n
               C1(k,j,i) = jx(k,j,i)*tmp
               C2(k,j,i) = jy(k,j,i)*tmp
               C3(k,j,i) = jz(k,j,i)*tmp
            END DO
         END DO
      END DO
      CALL fftp3d_complex_to_real(plancr,C1,rjx,MPI_COMM_WORLD)
      CALL fftp3d_complex_to_real(plancr,C2,rjy,MPI_COMM_WORLD)
      CALL fftp3d_complex_to_real(plancr,C3,rjz,MPI_COMM_WORLD)
#endif

!
! Allocates the arrays for the transfers

      ALLOCATE( uu(ktrn,ktrn) )
#ifdef MAGFIELD_
      ALLOCATE( bb(ktrn,ktrn) )
      ALLOCATE( ub(ktrn,ktrn) )
      ALLOCATE( bu(ktrn,ktrn) )
#endif
#ifdef ELSASSER_
      IF (elsa.eq.1) THEN
         ALLOCATE( px(n,n,ista:iend) )
         ALLOCATE( py(n,n,ista:iend) )
         ALLOCATE( pz(n,n,ista:iend) )
         ALLOCATE( mx(n,n,ista:iend) )
         ALLOCATE( my(n,n,ista:iend) )
         ALLOCATE( mz(n,n,ista:iend) )
         ALLOCATE( rpx(n,n,ksta:kend) )
         ALLOCATE( rpy(n,n,ksta:kend) )
         ALLOCATE( rpz(n,n,ksta:kend) )
         ALLOCATE( rmx(n,n,ksta:kend) )
         ALLOCATE( rmy(n,n,ksta:kend) )
         ALLOCATE( rmz(n,n,ksta:kend) )
         ALLOCATE( pp(ktrn,ktrn) )
         ALLOCATE( mm(ktrn,ktrn) )
         DO i = ista,iend               ! Elsasser variables
            DO j = 1,n
               DO k = 1,n
                  mx(k,j,i) = vx(k,j,i)-bx(k,j,i)
                  px(k,j,i) = bx(k,j,i)+vx(k,j,i)
                  my(k,j,i) = vy(k,j,i)-by(k,j,i)
                  py(k,j,i) = by(k,j,i)+vy(k,j,i)
                  mz(k,j,i) = vz(k,j,i)-bz(k,j,i)
                  pz(k,j,i) = bz(k,j,i)+vz(k,j,i)
               END DO
            END DO
         END DO
         DO k = ksta,kend
            DO j = 1,n
               DO i = 1,n
                  rmx(i,j,k) = rvx(i,j,k)-rbx(i,j,k)
                  rpx(i,j,k) = rbx(i,j,k)+rvx(i,j,k)
                  rmy(i,j,k) = rvy(i,j,k)-rby(i,j,k)
                  rpy(i,j,k) = rby(i,j,k)+rvy(i,j,k)
                  rmz(i,j,k) = rvz(i,j,k)-rbz(i,j,k)
                  rpz(i,j,k) = rbz(i,j,k)+rvz(i,j,k)
               END DO
            END DO
         END DO
      ENDIF
#endif
#ifdef HALLTERM_
      ALLOCATE ( jb(ktrn,ktrn) )
#endif
#ifdef ROTATION_
      ALLOCATE( para(ktrn,ktrn) )
      ALLOCATE( perp(ktrn,ktrn) )
#endif

      IF (heli.eq.1) THEN
         ALLOCATE( hh(ktrn,ktrn) )
#ifdef VORTICITY_
         ALLOCATE( wx(n,n,ista:iend) )
         ALLOCATE( wy(n,n,ista:iend) )
         ALLOCATE( wz(n,n,ista:iend) )
         CALL rotor3(vy,vz,wx,1)
         CALL rotor3(vx,vz,wy,2)
         CALL rotor3(vx,vy,wz,3)
#endif
#ifdef HALLTERM_
         ALLOCATE( jj(ktrn,ktrn) )
#endif
      ENDIF

!
! If continuing a previous run (cold=0), reads 
! 'kini.txt' and the arrays with the transfers

 RI : IF (myrank.eq.0) THEN

      IF (cold.eq.0) THEN

         OPEN(1,file='kini.txt',status='unknown')
         READ(1,*) kini
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_uu.' &
              // ext // '.out',form='unformatted')
         READ(1) uu
         CLOSE(1)
#ifdef MAGFIELD_
         OPEN(1,file=trim(odir) // '/transfer_bb.' &
              // ext // '.out',form='unformatted')
         READ(1) bb
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_ub.' &
              // ext // '.out',form='unformatted')
         READ(1) ub
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_bu.' &
              // ext // '.out',form='unformatted')
         READ(1) bu
         CLOSE(1)
#endif
#ifdef HALLTERM_
         OPEN(1,file=trim(odir) // '/transfer_jb.' &
              // ext // '.out',form='unformatted')
         READ(1) jb
         CLOSE(1)
#endif
#ifdef ROTATION_
         OPEN(1,file=trim(odir) // '/transfer_para.' &
              // ext // '.out',form='unformatted')
         READ(1) para
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_perp.' &
              // ext // '.out',form='unformatted')
         READ(1) perp
         CLOSE(1)
#endif

 HI :    IF (heli.eq.1) THEN
         OPEN(1,file=trim(odir) // '/transfer_hh.' &
              // ext // '.out',form='unformatted')
         READ(1) hh
         CLOSE(1)
#ifdef HALLTERM_
         OPEN(1,file=trim(odir) // '/transfer_jj.' &
              // ext // '.out',form='unformatted')
         READ(1) jj
         CLOSE(1)
#endif
         ENDIF HI

#ifdef ELSASSER_
         IF (elsa.eq.1) THEN
            OPEN(1,file=trim(odir) // '/transfer_pp.' &
                 // ext // '.out',form='unformatted')
            READ(1) pp
            CLOSE(1)
            OPEN(1,file=trim(odir) // '/transfer_mm.' &
                 // ext // '.out',form='unformatted')
            READ(1) mm
            CLOSE(1)
         ENDIF
#endif

      ELSE

         kini = 1

      ENDIF

      ENDIF RI

      CALL MPI_BCAST(kini,1,MPI_INTEGER,0,MPI_COMM_WORLD,ierr)

!
! Computes the transfer terms
!
! Energy transfers
!     uu(k,q) : -u_k.(u.grad u_q)
!     ub(k,q) : u_k.(b.grad b_q) (MAGFIELD_)
!     bu(k,q) : b_k.(b.grad u_q) (MAGFIELD_)
!     bb(k,q) : -b_k.(u.grad b_q) (MAGFIELD_)
!     jb(k,q) : -b_k.curl[curl(b_q) x b] = j_k.(b x j_q) (HALLTERM_)
! Helicity transfer
!     hh(k,q) : w_k.(u x w_q) (VORTICITY_)
!     hh(k,q) : b_k.(u x b_q) (MAGFIELD_)
!     jj(k,q) : -b_k.(j x b_q) (HALLTERM_)
! Elsasser transfers
!     pp(k,q) : -z+_k.(z-.grad z+_q) (ELSASSER_)
!     mm(k,q) : -z-_k.(z+.grad z-_q) (ELSASSER_)
! Anisitripic transfers
!     para(k,q) : -u_kpara.(u.grad u_qpara) (ROTH_SOL)
!     perp(k,q) : -u_kperp.(u.grad u_qperp) (ROTH_SOL)

      DO kk = kini,ktrn
         DO kq = 1,ktrn

            CALL shelltran(vx,vy,vz,rvx,rvy,rvz,vx,vy,vz,kk-1,kq-1,tmp)
            uu(kk,kq) = -tmp
#ifdef MAGFIELD_
            CALL shelltran(vx,vy,vz,rbx,rby,rbz,bx,by,bz,kk-1,kq-1,tmp)
            ub(kk,kq) = tmp
            CALL shelltran(bx,by,bz,rbx,rby,rbz,vx,vy,vz,kk-1,kq-1,tmp)
            bu(kk,kq) = tmp
            CALL shelltran(bx,by,bz,rvx,rvy,rvz,bx,by,bz,kk-1,kq-1,tmp)
            bb(kk,kq) = -tmp
#endif
#ifdef HALLTERM_
            CALL crosstran(jx,jy,jz,rbx,rby,rbz,kk-1,kq-1,tmp)
            jb(kk,kq) = tmp
#endif
#ifdef ROTH_SOL
            CALL paratran(vx,vy,vz,rvx,rvy,rvz,vx,vy,vz,kk-1,kq-1,tmp)
            para(kk,kq) = -tmp
            CALL perptran(vx,vy,vz,rvx,rvy,rvz,vx,vy,vz,kk-1,kq-1,tmp)
            perp(kk,kq) = -tmp
#endif

            IF (heli.eq.1) THEN
#ifdef VORTICITY_
               CALL crosstran(wx,wy,wz,rvx,rvy,rvz,kk-1,kq-1,tmp)
               hh(kk,kq) = tmp
#endif
#ifdef MAGFIELD_
               CALL crosstran(bx,by,bz,rvx,rvy,rvz,kk-1,kq-1,tmp)
               hh(kk,kq) = tmp
#endif
#ifdef HALLTERM_
               CALL crosstran(bx,by,bz,rjx,rjy,rjz,kk-1,kq-1,tmp)
               jj(kk,kq) = -tmp
#endif
            ENDIF

#ifdef ELSASSER_
            IF (elsa.ge.1) THEN
               CALL shelltran(px,py,pz,rmx,rmy,rmz,px,py,pz,kk-1,kq-1,tmp)
               pp(kk,kq) = -tmp
               CALL shelltran(mx,my,mz,rpx,rpy,rpz,mx,my,mz,kk-1,kq-1,tmp)
               mm(kk,kq) = -tmp
            ENDIF
#endif

         END DO

! Writes the results each 
! time a row is completed

 RO :    IF (myrank.eq.0) THEN

         OPEN(1,file='kini.txt',status='unknown')
         WRITE(1,*) kini
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_uu.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) uu
         CLOSE(1)
#ifdef MAGFIELD_
         OPEN(1,file=trim(odir) // '/transfer_bb.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) bb
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_ub.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) ub
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_bu.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) bu
         CLOSE(1)
#endif
#ifdef HALLTERM_
         OPEN(1,file=trim(odir) // '/transfer_jb.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) jb
         CLOSE(1)
#endif
#ifdef ROTATION_
         OPEN(1,file=trim(odir) // '/transfer_para.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) para
         CLOSE(1)
         OPEN(1,file=trim(odir) // '/transfer_perp.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) perp
         CLOSE(1)
#endif

 HO :    IF (heli.eq.1) THEN
         OPEN(1,file=trim(odir) // '/transfer_hh.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) hh
         CLOSE(1)
#ifdef HALLTERM_
         OPEN(1,file=trim(odir) // '/transfer_jj.' &
              // ext // '.out' ,form='unformatted')
         WRITE(1) jj
         CLOSE(1)
#endif
         ENDIF HO

#ifdef ELSASSER_
         IF (elsa.eq.1) THEN
            OPEN(1,file=trim(odir) // '/transfer_pp.' &
                 // ext // '.out' ,form='unformatted')
            WRITE(1) pp
            CLOSE(1)
            OPEN(1,file=trim(odir) // '/transfer_mm.' &
                 // ext // '.out' ,form='unformatted')
            WRITE(1) mm
            CLOSE(1)
         ENDIF
#endif

         OPEN(1,file='kini.txt')
         WRITE(1,*) kk+1
         CLOSE(1)

         ENDIF RO

      END DO

!
! End of TRANSFER3D

      CALL MPI_FINALIZE(ierr)
      CALL fftp3d_destroy_plan(plancr)
      CALL fftp3d_destroy_plan(planrc)
      DEALLOCATE( uu,vx,vy,vz )
      DEALLOCATE( rvx,rvy,rvz )
#ifdef MAGFIELD_
      DEALLOCATE( ub,bu,bb )
      DEALLOCATE( bx,by,bz )
      DEALLOCATE( C1,C2,C3 )
      DEALLOCATE( rbx,rby,rbz )
#endif 
#ifdef HALLTERM_
      DEALLOCATE( jb,jx,jy,jz )
      DEALLOCATE( rjx,rjy,rjz )
#endif 
#ifdef ROTATION_
      DEALLOCATE( para,perp )
#endif

      IF (heli.eq.1) THEN
         DEALLOCATE ( hh )
#ifdef VORTICITY_
         DEALLOCATE( wx,wy,wz )
#endif 
#ifdef HALLTERM_
         DEALLOCATE( jj )
#endif
      ENDIF
#ifdef ELSASSER_
      IF (elsa.eq.1) THEN
         DEALLOCATE( px,py,pz )
         DEALLOCATE( mx,my,mz )
         DEALLOCATE( rpx,rpy,rpz )
         DEALLOCATE( rmx,rmy,rmz )
         DEALLOCATE( pp,mm )
      ENDIF
#endif

      END PROGRAM TRANSFER3D

