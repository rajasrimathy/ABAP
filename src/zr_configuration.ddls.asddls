@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: '##GENERATED ZCONFIGURATION'
define root view entity ZR_CONFIGURATION
  as select from zconfiguration
{
  key z_configuration_uuid  as ZConfigurationUUID,
      z_id                  as ZID,
      z_grant_type          as ZGrantType,
      z_client_id           as ZClientID,
      z_client_secret       as ZClientSecret,
      @Semantics.user.createdBy: true
      z_createdby           as ZCreatedby,
      @Semantics.systemDateTime.createdAt: true
      z_createdate          as ZCreatedate,
      @Semantics.user.localInstanceLastChangedBy: true
      z_lastchangedby       as ZLastchangedby,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      z_lastchangedate      as ZLastchangedate,
      @Semantics.systemDateTime.lastChangedAt: true
      z_locallastchangedate as ZLocallastchangedate

}
