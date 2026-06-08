# Liste -Roots per Get-AclAssessment.ps1
# Generato dall incrocio ElencoSharesMG.xlsx - solo share dati, niente annidate.
# I percorsi sono locali al rispettivo server. Verificare lettera di unita prima del lancio.
#
# IMPORTANTE: questo file va caricato con DOT-SOURCING, non eseguito.
#   . .\Roots_MG.ps1            # nota il punto + spazio iniziale
# Eseguirlo normalmente (.\Roots_MG.ps1) definisce le variabili in uno scope
# figlio che viene scartato al ritorno: nella sessione $Roots_* resterebbero
# vuote e Get-AclAssessment riceverebbe $null.
#
# Uso tipico:
#   . .\Roots_MG.ps1
#   .\Get-AclAssessment.ps1 -Roots $Roots_ITTNFS01 -OutputDir C:\Temp\Assessment -ServerLabel ITTNFS01 -Verbose

# ================================================================
# ITTNFS01  -  Novaledo (TN)  -  60 root
# ================================================================
$Roots_ITTNFS01 = @(
    'C:\DSC\SW'                                             # share: SW
    'D:\Automation'                                         # share: Automation$
    'D:\GestProdotti'                                       # share: Prodotti$
    'E:\AccordiTangerine'                                   # share: AccordiTangerine$
    'E:\Acquisti'                                           # share: Acquisti$
    'E:\AssicurazioneQualita'                               # share: AssicurazioneQualita$
    'E:\Biomassa'                                           # share: Biomassa$
    'E:\Contabilita'                                        # share: Contabilita$
    'E:\ControlloGestione'                                  # share: ControlloGestione$
    'E:\COVID-19'                                           # share: COVID-19$
    'E:\Direzione'                                          # share: Direzione$
    'E:\Festo'                                              # share: Festo$
    'E:\IngressiPersonaleEsterno'                           # share: IngressiPersonaleEsterno$
    'E:\Manutenzione'                                       # share: Manutenzione$
    'E:\Marketing'                                          # share: Marketing$
    'E:\Produzione'                                         # share: Produzione$
    'E:\RicercaSviluppo'                                    # share: RicercaSviluppo$
    'E:\Segreteria'                                         # share: Segreteria$
    'E:\UfficioPersonale'                                   # share: UfficioPersonale$
    'E:\Vendite'                                            # share: Vendite$
    'F:\Amministrazione'                                    # share: Amministrazione$
    'F:\HumanResources'                                     # share: HumanResources$
    'F:\Industrialization'                                  # share: Industrialization
    'F:\Prenotazioni'                                       # share: Prenotazioni$
    'F:\Reception_Amministrazione'                          # share: Reception_Amministrazione$
    'F:\SupplyChain'                                        # share: SupplyChain$
    'F:\Tangerine'                                          # share: Tangerine$
    'F:\TrackingProgetti'                                   # share: TrackingProgetti$
    'F:\UfficioGrafico'                                     # share: UfficioGrafico$
    'F:\YO-GBG'                                             # share: YO-GBG$
    'G:\_MG_'                                               # share: _MG_$
    'G:\BusinessDevelopment'                                # share: BusinessDevelopment$
    'G:\ControlloQualita'                                   # share: ControlloQualita$
    'G:\DirezioneProdotto'                                  # share: DirezioneProdotto$
    'G:\DirezioneStabilimento'                              # share: DirezioneStabilimento$
    'G:\Formazione'                                         # share: Formazione$
    'G:\ManualeSistemaIntegrato'                            # share: ManualeSistemaIntegrato$
    'G:\Modello231'                                         # share: Modello231$
    'G:\NuoviProgetti'                                      # share: NuoviProgetti$
    'G:\Progetti2017_2018'                                  # share: Progetti2017_2018$
    'G:\ProgettiAreaTecnica'                                # share: ProgettiAreaTecnica$
    'G:\Reception-HR'                                       # share: Reception-HR$
    'G:\RendicontazioneEnergia'                             # share: RendicontazioneEnergia$
    'G:\UfficioTecnico'                                     # share: UfficioTecnico$
    'H:\BackupIndustria'                                    # share: BackupIndustria$
    'H:\dashboard'                                          # share: dashboard$
    'H:\fsvr\_altro'                                        # share: _altrovr$
    'H:\fsvr\Manutenzione'                                  # share: Manutenzionevr$
    'H:\fsvr\RicercaSviluppo'                               # share: RicercaSviluppovr$
    'H:\fsvr\SupplyChain'                                   # share: SupplyChainvr$
    'H:\IT'                                                 # share: IT$
    'H:\JamfRepo'                                           # share: JamfRepo$
    'H:\LaboratorioAnalisiMG'                               # share: LaboratorioAnalisiMG$
    'H:\Malaysia'                                           # share: Malaysia$
    'H:\MGProductionSystem'                                 # share: MGProductionSystem$
    'H:\RecuperoCrediti'                                    # share: RecuperoCrediti$
    'H:\Rifiuti'                                            # share: Rifiuti$
    'H:\SinistroVibrovaglio'                                # share: SinistroVibrovaglio$
    'H:\Sostenibilità'                                      # share: Sostenibilità$
    'H:\Stage'                                              # share: Stage$
)

# .\Get-AclAssessment.ps1 -Roots $Roots_ITTNFS01 -OutputDir C:\Temp\Assessment -ServerLabel ITTNFS01 -Verbose

# ================================================================
# ITSAFS01  -  Sanguinetto (VR)  -  2 root
# ================================================================
$Roots_ITSAFS01 = @(
    'C:\DSC\SW'                                             # share: SW
    'E:\Share'                                              # share: Share$
)

# .\Get-AclAssessment.ps1 -Roots $Roots_ITSAFS01 -OutputDir C:\Temp\Assessment -ServerLabel ITSAFS01 -Verbose

# ================================================================
# MYKSSRV002  -  Malesia  -  18 root
# ================================================================
$Roots_MYKSSRV002 = @(
    'E:\Accounting'                                         # share: Accounting$
    'E:\Controlling'                                        # share: Controlling$
    'E:\Finance'                                            # share: Finance$
    'E:\HumanResources'                                     # share: HumanResources$
    'E:\HumanResources2'                                    # share: HumanResources2$
    'E:\IT'                                                 # share: IT$
    'E:\Maintenance'                                        # share: Maintenance$
    'E:\ManagementSystem'                                   # share: ManagementSystem$
    'E:\MD_Files'                                           # share: MD_Files$
    'E:\Operations'                                         # share: Operations$
    'E:\ProductDevelopment'                                 # share: ProductDevelopment$
    'E:\QualityAssurance'                                   # share: QualityAssurance$
    'E:\QualityControl'                                     # share: QualityControl$
    'E:\ResearchDevelopment'                                # share: ResearchDevelopment$
    'E:\Sales'                                              # share: Sales$
    'E:\SupplyChain'                                        # share: SupplyChain$
    'E:\TechnicalOffice'                                    # share: TechnicalOffice$
    'E:\TMP DeevaFile'                                      # share: TMP DeevaFile
)

# .\Get-AclAssessment.ps1 -Roots $Roots_MYKSSRV002 -OutputDir C:\Temp\Assessment -ServerLabel MYKSSRV002 -Verbose
