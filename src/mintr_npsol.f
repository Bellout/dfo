      
      SUBROUTINE MINTR( N   , X0   , MVAL  , DELTA, LWRBND, UPRBND,
     *                  A   , LDA  , NCLIN , NCNLN, WRK   , LWRK  ,
     *                  IWRK, LIWRK, INFORM, METHOD )
    

C
C  *******************************************************************
C  THIS SUBROUTINE FINDS THE MINIMUM OF THE QUADRATIC MODEL WITHIN THE
C  GIVEN REGION. THE REGION IS DEFINED BY THE INTERSECTION OF THE
C  TRUST REGION OF RADIUS DELTA AND THE ANALYTICALLY DEFINED FEASIBLE 
C  SET OF THE ORIGINAL PROBLEM.
C
C                         T       T
C                MIN [GMOD X+0.5*X HMOD X]
C         
C                  X0-DELTA <=  X   <= XO+DELTA
C        S.T.
C                               / X  \
C                        LB <= ( AX   ) <= UB
C                               \C(X)/
C  PARAMETERS:
C
C   N      (INPUT)  DIMENTION OF THE PROBLEM
C
C   X0     (INPUT)  ARRAY OF LENGTH N CONTAINING THE CENTER OF THE TRUST
C                   REGION
C          (OUTPUT) CONTAINS THE OPTIMAL POINT FOR THE MODEL
C
C   MVAL   (OUTPUT) THE VALUE OF THE MODEL AT THE OPTIMAL POINT
C
C   DELTA  (INPUT)  TRUST REGION RADIUS
C
C   LWRBND (INPUT)  ARRAY OF LENGHT N+NCLIN+NCNLN OF LOWER BOUNDS 
C
C   UPRBND (INPUT)     ''       ''         ''        UPPER   ''
C
C   NCLIN  (INPUT)  NUMBER OF LINEAR ANALYTIC CONSTRAINTS
C
C   A      (INPUT)  (LDA X N) MATRIX OF LINEAR ANALYTIC CONSTRAINTS
C  
C   NCNLN  (INPUT)  NUMBER OF NOLINEAR INEQUALITIES (DIFFICULT AND EASY)
C
C   WRK             REAL SPACE WORKING ARRAY
C
C   IWRK            INTEGER SPACE WORKING ARRAY
C
C   INFORM (OUTPUT) INFORMATION ON EXIT
C              0    SUCCESSFUL MINIMIZATION
C              1    THE DERIVATIVES OF THE CONSTRAINT OR SOME PARAMETER
C                   SET BY THE USER IS INCORRECT
C              2    MINIMIZATION FAILED FOR SOME REASON
C
C  
C   METHOD (INPUT)  METHOD FOR HANDLING CONSTRAINTS
C              1    MINIMIZE MODEL OF OBJECTIVE S.T. MODELS OF CONSTRAINTS
C              2    MINIMIZE MERIT FUNCTION OF THE MODELS OF CON AND OBJ
C             3,4   MINIMIZE MODEL OF A MERIT FUNCTION (EXACT OR QUAD)
C
C  **********************************************************************
C


      INTEGER           N ,  NCLIN , NCNLN, LIWRK, LWRK, IWRK(LIWRK),
     +                  LDA, INFORM, METHOD

 
      DOUBLE PRECISION  X0(N), MVAL, DELTA, LWRBND(N+NCLIN+NCNLN),
     *                  UPRBND(N+NCLIN+NCNLN), WRK(LWRK), A(LDA*N) 

C
C  COMMON VARIABLES
C

C
C  PRINTOUT PARAMETERS
C
      INTEGER          IOUT  , IPRINT
      DOUBLE PRECISION MCHEPS, CNSTOL

      COMMON / DFOCM /  IOUT, IPRINT, MCHEPS, CNSTOL
      SAVE / DFOCM /
C
C  EXTERNAL SUBROUTINES
C

      EXTERNAL          FUNOBJ, FUNCON

      DOUBLE PRECISION DDOT

      EXTERNAL         DDOT

C
C  LOCAL VARIABLES
C
      
      DOUBLE PRECISION  VAL, TOL, HALF, SMALL, ZERO, ONE

      PARAMETER         (HALF = 0.5D0, SMALL  = 1.0D-5, ZERO=0.0D0,
     *                   ONE  = 1.0D0)
      INTEGER           I   , NLND, LNNEED, IBL   , IBU   , LBL  ,  
     *                  LBU , IC  , ICJAC , ICLMDA, ICURIW, ICURW,
     *                  IR  , INF , IGRAD , IISTAT, LENIW , LENW ,
     *                  ITER, LDCJAC, NCONT
      INTRINSIC         MAX , MIN
      INCLUDE 'dfo_model_inc.inc'
C
C  SET THE COMMON PARAMETER 'IPOPT' (DEFINED IN DFO_MODEL_INC) TO 0
C  SINCE WE ARE USING NPSOL
C
      USEIPOPT=0
      IF (METHOD .EQ. 2) THEN 
         USEMERIT=.TRUE.
      ELSE
         USEMERIT=.FALSE.
      ENDIF
      NCONT=NCON
      IF (NCNLN .LE. NNLN .AND. .NOT.USEMERIT) NCON=0
C
C  SUBROUTINES AND FUNCTIONS CALLED:
C
C    APPLICATION     :       FUNCON, FUNOBJ
C    NPSOL           :       NPSOL, NPOPTN 
C    BLAS            :       DCOPY, DDOT
C    FORTRAN SUPPLIED:       MIN, MAX
C

      
C 
C  PARTITION THE REAL SPACE
C
      
      NLND   = MAX(1,NCNLN)
      IBL    = 1
      IBU    = IBL+N+NCLIN+NCNLN
      IC     = IBU+N+NCLIN+NCNLN
      ICJAC  = IC+NLND
      ICLMDA = ICJAC+NLND*N
      IGRAD  = ICLMDA+N+NCLIN+NCNLN
      IR     = IGRAD+N
      ICURW  = IR+N*N
      LENW   = LWRK-ICURW+1
      
C
C  CHECK IF THE REAL SPACE IS SUFFICIENT
C
 
      LNNEED = 2*N*N+N*NCLIN+2*N*NCNLN+20*N+11*NCLIN+21*NCNLN

      IF (LENW.LT.LNNEED) THEN
        IF (IPRINT .GE. 0) WRITE(IOUT,9000) LNNEED
        STOP
      ENDIF

C 
C  PARTITION THE INTEGER SPACE
C
      IISTAT =1
      ICURIW  =IISTAT+N+NCLIN+NCNLN
      LENIW=LIWRK-ICURIW+1

C
C  CHECK IF THE INTEGER SPACE IS SUFFICIENT
C
      IF (LENIW.LT.3*N+NCLIN+2*NCNLN) THEN
        IF (IPRINT .GE. 0) WRITE (IOUT,9001) 3*N+NCLIN+2*NCNLN
        STOP
      ENDIF

C
C  SET THE JACOBIAN DIMENSION FOR NPSOL
C
      
      LDCJAC=NLND
C
C  COMBINE TRUST REGION BOUNDS WITH THE SIMPLE BOUNDS OF THE PROBLEM
C
      LBL=IBL-1
      LBU=IBU-1
      DO 10 I=1,N
        WRK(LBL+I)=MAX(X0(I)-DELTA, LWRBND(I))
        WRK(LBU+I)=MIN(X0(I)+DELTA, UPRBND(I))
 10   CONTINUE

      IF (NCLIN+NCNLN .GT. 0) THEN
        CALL DCOPY(NCLIN+NCNLN, LWRBND(N+1), 1, WRK(IBL+N), 1)
        CALL DCOPY(NCLIN+NCNLN, UPRBND(N+1), 1, WRK(IBU+N), 1)
      ENDIF
C
C  SET CONSTRAINT TOLERANCE
C

      TOL=CNSTOL
C
C  IF THERE ARE NO NONLINEAR CONSTRAINTS SET THE CONSTRAINT 
C  TOLERANCE, USED BY NPSOL, TO A DEFAULT VALUE
C
      CALL NPOPTN( 'NOLIST' )
      IF ( NCNLN .EQ. 0 ) TOL = 1.0D-8

      IF ( TOL .GE. 1.0D0 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D0' )
      ELSE IF ( TOL .GE. 1.0D-1 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-1' )
      ELSE IF ( TOL .GE. 1.0D-2 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-2' )
      ELSE IF ( TOL .GE. 1.0D-3 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-3' )
      ELSE IF ( TOL .GE. 1.0D-4 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-4' )
      ELSE IF ( TOL .GE. 1.0D-5 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-5' )
      ELSE IF ( TOL .GE. 1.0D-6 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-6' )
      ELSE IF ( TOL .GE. 1.0D-7 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-7' )
      ELSE IF ( TOL .GE. 1.0D-8 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-8' )
      ELSE IF ( TOL .GE. 1.0D-9 ) THEN 
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-9' )
      ELSE     
        CALL NPOPTN( 'FEASIBILITY TOLERANCE = 1.0D-10' )
      ENDIF
      CALL NPOPTN( 'PRINT LEVEL = 0' )
         CALL NPSOL( N          , NCLIN       , NCNLN     , LDA       , 
     *               LDCJAC     , N           , A         , WRK(IBL)  ,
     *               WRK(IBU)   , FUNCON      , FUNOBJ    , INF       , 
     *               ITER       , IWRK(IISTAT), WRK(IC)   , WRK(ICJAC),
     *               WRK(ICLMDA), MVAL        , WRK(IGRAD), WRK(IR)   ,
     *               X0         , IWRK(ICURIW), LENIW     , WRK(ICURW), 
     *               LENW       )        


       IF (INF.EQ.0) THEN
         IF( IPRINT.GE.3 )    WRITE(IOUT,8000) 
         INFORM=0
       ELSE IF (INF.EQ.1) THEN
         IF( IPRINT.GE.3 )    WRITE(IOUT,8001) 
         INFORM=0
       ELSE IF (INF.EQ.2) THEN
         IF( IPRINT.GE.3 )    WRITE(IOUT,8002) 
         INFORM=2
       ELSE IF (INF.EQ.3) THEN
         IF( IPRINT.GE.3 )    WRITE(IOUT,8003) 
         INFORM=3
       ELSE IF (INF.EQ.4) THEN
         IF( IPRINT.GE.3 )    WRITE(IOUT,8004) 
         INFORM=0
       ELSE IF (INF.EQ.6) THEN
         IF( IPRINT.GE.3 )    WRITE(IOUT,8006) 
         INFORM=2
       ELSE IF (INF.EQ.7) THEN
         IF( IPRINT.GE.3 )   WRITE(IOUT,8007) 
         INFORM=1
       ELSE IF (INF.EQ.9) THEN
         IF( IPRINT.GE.3 )   WRITE(IOUT,8009) 
         INFORM=1
       ENDIF

       IF ( INF .EQ. 6 .OR. INF .EQ. 4  .OR. INF .EQ. 1 ) THEN
         INFORM = 0
         DO 40 I=1, N
           IF ( X0(I) .LT. WRK(LBL+I) - CNSTOL .OR.
     *          X0(I) .GT. WRK(LBU+I) + CNSTOL     ) 
     *         INFORM = 2
 40      CONTINUE
         IF ( NCLIN .GT. 0 .AND. INFORM .EQ. 0 ) THEN
           DO 70 I=1, NCLIN 
             VAL = DDOT(N, A(I), LDA, X0, 1 )
             IF ( VAL .LT. LWRBND(N+I) - CNSTOL .OR.
     *            VAL .GT. UPRBND(N+I) + CNSTOL     ) 
     *            INFORM = 2
 70        CONTINUE
         ENDIF
         IF ( NCNLN .GT. 0 .AND. INFORM .EQ. 0 ) THEN
           CALL FUNCON(1 , NCNLN  , N         , LDCJAC, IWRK(ICURIW),
     *                 X0, WRK(IC), WRK(ICJAC), 1     )
           DO 60 I=1, NCNLN 
             IF ( WRK(IC+I-1) .LT. LWRBND(N+NCLIN+I) - CNSTOL .OR.
     *            WRK(IC+I-1) .GT. UPRBND(N+NCLIN+I) + CNSTOL     ) 
     *            INFORM = 3
 60        CONTINUE
         ENDIF
       ENDIF
       IF ( NCON .GT. 0 .AND. .NOT. USEMERIT ) THEN
         CALL FUNCON(1 , NCNLN  , N         , LDCJAC, IWRK(ICURIW),
     *               X0, WRK(IC), WRK(ICJAC), 1     )
         CALL DCOPY(NCON, WRK(IC+NNLN), 1, WRK, 1)
       ENDIF
       NCON=NCONT
     
      RETURN

 
 9000  FORMAT( ' DFO: MINTR: *** ERROR: LWRK TOO SMALL!' /
     +        '  DFO:           IT SHOULD BE AT LEAST ',I12 )
 9001  FORMAT( ' DFO: MINTR: *** ERROR: LIWRK TOO SMALL!' /
     +        '  DFO:           IT SHOULD BE AT LEAST ', I12 )
 8000  FORMAT( ' DFO: MINTR: SUCCESSFUL MINIMIZATION' )
 8001  FORMAT( ' DFO: MINTR: NO FURTHER IMPROVEMENT CAN BE OBTAINED' )
 8002  FORMAT( ' DFO: MINTR: NO FEASIBLE POINT FOUND FOR LINEAR' /
     +        '  DFO:       CONSTRAINTS AND BOUNDS' )
 8003  FORMAT( ' DFO: MINTR: NO FEASIBLE POINT FOUND FOR ' /
     +        '  DFO:        NONLINEAR CONSTRAINTS' )
 8004  FORMAT( ' DFO: MINTR: MAXIMUM NUMBER OF ITERATIONS REACHED' )
 8006  FORMAT( ' DFO: MINTR: NPSOL QUIT BEFORE X SATISFIED K-T CONDIT.')
 8007  FORMAT( ' DFO: MINTR: DERIVATIVES OF CONSTRAINTS ARE INCORRECT' )
 8009  FORMAT( ' DFO: MINTR: AN INPUT PARAMETER IS INVALID' )

       END









