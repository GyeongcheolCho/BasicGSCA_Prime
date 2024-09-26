function [INI,TABLE,ETC]=BasicGSCA(Data,W,C,B,N_Boot,Max_iter,Min_limit)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% BasicGSCA() - MATLAB function to perform a basic version of Generalzied %
%               Structured Component Analysis (GSCA).                     %
% Author: Gyeongcheol Cho                                                 %
% Last Revision Date: September 26, 2024                                  % 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Input arguments:                                                        %
%   Data = an N by J matrix of scores for N individuals on J indicators   %
%   W = a J by P matrix of weight parameters                              %
%   C = a P by J matrix of loading parameters                             %
%   B = a P by P matrix of path coefficients                              %
%   N_Boot = Integer representing the number of bootstrap samples for     %
%            calculating standard errors (SE) and 95% confidence          %
%            intervals (CI).                                              %
%   Max_iter = Maximum number of iterations for the Alternating Least     % 
%              Squares (ALS) algorithm                                    %
%   Min_limit = Tolerance level for ALS algorithm                         %
%   Flag_Parallel = Logical value to determine whether to use parallel    %
%                   computing for bootstrapping                           %
% Output arguments:                                                       %
%   INI: Strucutre array containing goodness-of-fit values, R-squared     % 
%        values, and matrices parameter estimates                         %
%     .GoF = [FIT_D,   OPE_D;                                             %
%             FIT_M_D, OPE_M_D;                                           %
%             FIT_S_D, OPE_S_D];                                          %
%     .R2m = Vector of R-squared values for dependent variables           %
%               in the measurement model                                  %
%     .R2s = Vector of R-squared values for dependent variables           %
%               in the structural model                                   %
%     .W: a J by P matrix of weight estimates                             %
%     .C: a P by J matrix of loading estimates                            %
%     .B: a P by P matrix of path coefficient estimates                   %
%  TABLE: Structure array containing tables of parameter estimates, their %
%         SEs, 95% CIs,and other statistics                               %
%     .W: Table for weight estimates                                      %
%     .C: Table for loading estimates                                     %
%     .B: Table for path coefficients estimates                           %
%  ETC: a structure array including bootstrapped parameter estmates       %
%     .W_Boot: Matrix of bootstrapped weight estimates                    %
%     .C_Boot: Matrix of bootstrapped loading estimates                   %
%     .B_Boot: Matrix of bootstrapped path coefficient estimates          %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% (1) Preliminary stage
    Z=Data;  
    [N,J]=size(Z);
    P=size(B,1);
    T=J+P;
           
    % index
    W0=W~=0; Nw=sum(sum(W0,1),2);
    C0=C~=0; Nc=sum(sum(C0,1),2);
    B0=B~=0; Nb=sum(sum(B0,1),2);
    B0=B~=0;
    ind_Cdep=sum(C0,1)>0; Jy = sum(ind_Cdep,2); loc_Cdep=find(ind_Cdep);
    ind_Bdep=sum(B0,1)>0; Py = sum(ind_Bdep,2); loc_Bdep=find(ind_Bdep); Ty = Jy+Py;
    ind_Adep=[ind_Cdep, ind_Bdep];
    loc_w_t=cell(1,P);
    loc_b_t=cell(1,P);
    for p=1:P
        loc_w_t{1,p}=find(W(:,p))';
        loc_b_t{1,p}=find(B(:,p))';
    end
    loc_c_t=cell(1,J);
    for j=1:J
        loc_c_t{1,j}=find(C(:,j))';
    end
 %       ind_exo=find(structural_eq);
    % Setting the intital values for A,W    
        W(W0)=1;
%% (3) Estimation of paramters
    [est_W,est_C,est_B,vec_err]=ALS_Basic(Z,W,W0,C0,B0,ind_Adep,Min_limit,Max_iter,N,J,P,T,Jy,Py,loc_Cdep,loc_Bdep);            
    INI.W=est_W;
    INI.C=est_C;
    INI.B=est_B;
    R_squared_dep=ones(1,Ty)-vec_err;
    R_squared=zeros(1,T);
    R_squared(1,ind_Adep)=R_squared_dep;
    Eval=[mean(R_squared(1,[ind_Cdep,ind_Bdep])),NaN; %% FIT_D
          mean(R_squared(1,[ind_Cdep,false(1,P)])),NaN; %% FIT_M_D    
          mean(R_squared(1,[false(1,J),ind_Bdep])),NaN]; %% FIT_S_D
    INI.GoF=Eval;
    INI.R2_m = R_squared(1,[ind_Cdep,false(1,P)]);
    INI.R2_s = R_squared(1,[false(1,J),ind_Bdep]);
      
%% (4) Estimation parameters for N_Boot
    if N_Boot<100
        TABLE.W=[];
        TABLE.C=[];
        TABLE.B=[];
        ETC=[];
    else
        W_Boot=zeros(Nw,N_Boot);
        C_Boot=zeros(Nc,N_Boot);
        B_Boot=zeros(Nb,N_Boot);
        delOPE_c_Boot=zeros(Nc,N_Boot);
        delOPE_b_Boot=zeros(Nb,N_Boot);
        OPE_Boot=zeros(3,N_Boot);    
        if Flag_Parallel
            parfor b=1:N_Boot
                [Z_ib,Z_oob]=GC_Boot(Z);
                mean_Z_ib=mean(Z_ib);
                std_Z_ib=std(Z_ib,1);
                [W_b,C_b,B_b,~]=ALS_Basic(Z_ib,W,W0,C0,B0,ind_Adep,Min_limit,Max_iter,N,J,P,T,Jy,Py,loc_Cdep,loc_Bdep);            
                W_Boot(:,b)=W_b(W0);
                C_Boot(:,b)=C_b(C0);
                B_Boot(:,b)=B_b(B0);
        
            %   (4) Predictabiliy 
            %   (4a) Err for model
                %(4a-1) Scaling for Z_oob, est_W
                N_oob=size(Z_oob,1);
                Z_oob=(Z_oob-ones(N_oob,1)*mean_Z_ib)./(ones(N_oob,1)*std_Z_ib);
                CV_oob=Z_oob*W_b;             
                %(4a-2) to estimate Err(b)
                e_oob=[Z_oob,CV_oob]-CV_oob*[C_b,B_b];
                ope_full=sum(e_oob.^2,1)/N_oob;
        
                em_oob=ope_full(:,1:J);
                es_oob=ope_full(:,(J+1):T);
        
                em_dep_oob=em_oob(:,ind_Cdep);
                es_dep_oob=es_oob(:,ind_Bdep);
        
                sum_em_dep_oob = sum(em_dep_oob,2);
                sum_es_dep_oob = sum(es_dep_oob,2);
                OPE_Boot(:,b)=[(sum_em_dep_oob+sum_es_dep_oob)/Ty;sum_em_dep_oob/Jy;sum_es_dep_oob/Py]; % Error_oob for the measurement model

                [delOPE_c_Boot(:,b),delOPE_b_Boot(:,b)]=Gen_delOPE(Z_oob,CV_oob, ...
                                                                em_oob,es_oob, ...
                                                                C_b,B_b,C0,B0, ...
                                                                loc_c_t,loc_b_t,loc_Cdep,loc_Bdep, ...
                                                                N_oob,Nc,Nb);
            end
        else
            for b=1:N_Boot
                [Z_ib,Z_oob]=GC_Boot(Z);
                mean_Z_ib=mean(Z_ib);
                std_Z_ib=std(Z_ib,1);
                [W_b,C_b,B_b,~]=ALS_Basic(Z_ib,W,W0,C0,B0,ind_Adep,Min_limit,Max_iter,N,J,P,T,Jy,Py,loc_Cdep,loc_Bdep);            
                W_Boot(:,b)=W_b(W0);
                C_Boot(:,b)=C_b(C0);
                B_Boot(:,b)=B_b(B0);
        
            %   (4) Predictabiliy 
            %   (4a) Err for model
                %(4a-1) Scaling for Z_oob, est_W
                N_oob=size(Z_oob,1);
                Z_oob=(Z_oob-ones(N_oob,1)*mean_Z_ib)./(ones(N_oob,1)*std_Z_ib);
                CV_oob=Z_oob*W_b;             
                %(4a-2) to estimate Err(b)
                e_oob=[Z_oob,CV_oob]-CV_oob*[C_b,B_b];
                ope_full=sum(e_oob.^2,1)/N_oob;
        
                em_oob=ope_full(:,1:J);
                es_oob=ope_full(:,(J+1):T);
        
                em_dep_oob=em_oob(:,ind_Cdep);
                es_dep_oob=es_oob(:,ind_Bdep);
        
                sum_em_dep_oob = sum(em_dep_oob,2);
                sum_es_dep_oob = sum(es_dep_oob,2);
                OPE_Boot(:,b)=[(sum_em_dep_oob+sum_es_dep_oob)/Ty;sum_em_dep_oob/Jy;sum_es_dep_oob/Py]; % Error_oob for the measurement model

                [delOPE_c_Boot(:,b),delOPE_b_Boot(:,b)]=Gen_delOPE(Z_oob,CV_oob, ...
                                                                em_oob,es_oob, ...
                                                                C_b,B_b,C0,B0, ...
                                                                loc_c_t,loc_b_t,loc_Cdep,loc_Bdep, ...
                                                                N_oob,Nc,Nb);
            end
        end

    %% (5) Calculation of statistics
    % Predictiablity
        Eval(:,2)=[mean(OPE_Boot(1,:),2);mean(OPE_Boot(2,:),2);mean(OPE_Boot(3,:),2)];
        INI.GoF=Eval;
    % CI
        alpha=.05;
        CI=[alpha/2,alpha,1-alpha,1-(alpha/2)];
        loc_CI=round(CI*(N_Boot-1))+1; % .025 .05 .95 .975
          
    % basic statistics for parameter
        TABLE.W=para_stat(est_W(W0),W_Boot,loc_CI,[]);
        if Jy>0; TABLE.C=para_stat(est_C(C0),C_Boot,loc_CI,delOPE_c_Boot); end
        if Py>0; TABLE.B=para_stat(est_B(B0),B_Boot,loc_CI,delOPE_b_Boot); end
        ETC.W_Boot=W_Boot;
        ETC.C_Boot=C_Boot;
        ETC.B_Boot=B_Boot;        
    end
end
function Table=para_stat(est_mt,boot_mt,CI_mp,delOPE_p_q_Boot)
    flag_pet = true;
    if isempty(delOPE_p_q_Boot); flag_pet = false; end
    boot_mt=sort(boot_mt,2);
    SE=std(boot_mt,0,2);
    Table=[est_mt,SE,boot_mt(:,CI_mp(1,1)),boot_mt(:,CI_mp(1,4))]; 
    if flag_pet
        delOPE_p_q_Boot=sort(delOPE_p_q_Boot,2);
        Table=[Table,delOPE_p_q_Boot(:,CI_mp(1,2)),mean(delOPE_p_q_Boot<=0,2)];
    end
end
function [in_sample,out_sample,index,N_oob]=GC_Boot(Data)
    N=size(Data,1); 
    index=ceil(N*rand(N,1));
    in_sample=Data(index,:); 
    index_oob=(1:N)'; index_oob(index)=[];
    out_sample=Data(index_oob,:);
    N_oob=length(index_oob);
end
function [delOPE_c,delOPE_b]=Gen_delOPE(Z_oob,CV_oob, ...
                                         em_oob,es_oob, ...
                                         C_b,B_b,C0,B0, ...
                                         loc_c_t,loc_b_t,loc_Cdep,loc_Bdep, ...
                                         N_oob,Nc,Nb)
    i_c=0;
    delOPE_c=zeros(Nc,1);
    loc_c_t_set=loc_c_t; % for parfor
    for jy_dep=loc_Cdep
%   (4b) VIMP for each parameter
        c_jy = C_b(:,jy_dep);
        zy = Z_oob(:,jy_dep);    
        ope_jy_k = em_oob(1,jy_dep);
        for j=loc_c_t_set{1,jy_dep}
            i_c=i_c+1;                
            ind_cq_p0=C0(:,jy_dep);
            ind_cq_p0(j)=false;                
            e_j_q_k=zy-CV_oob(:,ind_cq_p0)*c_jy(ind_cq_p0,1);
            ope_j_q_k=(sum(e_j_q_k.^2,1)/N_oob);
            delOPE_c(i_c,1)=ope_j_q_k-ope_jy_k;  % for parfor
        end
    end

    i_b=0;
    delOPE_b=zeros(Nb,1);
    loc_b_t_set=loc_b_t; % for parfor
    for q_dep=loc_Bdep
%   (4b) VIMP for each parameter
        bq = B_b(:,q_dep);
        ry = CV_oob(:,q_dep);    
        ope_q_k = es_oob(1,q_dep);
        for p=loc_b_t_set{1,q_dep}
            i_b=i_b+1;                
            ind_bq_p0=B0(:,q_dep);
            ind_bq_p0(p)=false;                
            e_p_q_k=ry-CV_oob(:,ind_bq_p0)*bq(ind_bq_p0,1);
            ope_p_q_k=(sum(e_p_q_k.^2,1)/N_oob);
            delOPE_b(i_b,1)=ope_p_q_k-ope_q_k;  % for parfor
        end
    end
end