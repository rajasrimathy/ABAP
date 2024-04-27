@EndUserText.label: 'Payment Details'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@Metadata.allowExtensions: true
define root view entity ZC_PAYMENTDETAILS
provider contract transactional_query as 
projection on ZR_PAYMENTDETAILS
{
    key ZPaymentUuid,
    @EndUserText.label: 'Payment File Reference'
    ZPaymentFileReference,
    @EndUserText.label: 'File Content'
    ZFileContent,
    @EndUserText.label: 'Encrypted File'
    ZEncryptedfile,
    @EndUserText.label: 'Payment Status'
    ZPaymentstatus,
    @EndUserText.label: 'Bank Processed Status'
    ZBankProcessedStatus,
    ZPaymentstatuscode,
    @EndUserText.label: 'Payment Message Id'
    ZPaymentmessageid,
    @EndUserText.label: 'Payment Sync'
    ZPaymentsync,
    @EndUserText.label: 'Status Sync'
    ZStatussync,
    @EndUserText.label: 'Client Code'
    ZClientcode,
    @EndUserText.label: 'Message Source Code'
    ZMessagesourcecode,
    ZCreatedby,
    ZCreatedate,
    ZLastchangedby,
    ZLastchangedate,
    ZLocallastchangedate,
    /* Associations */
    _Log:redirected to composition child ZC_PAYMENTLOG,
    _StatusLog: redirected to composition child ZC_STATUSLOG,
    _InstrumentLog:redirected to composition child ZC_INSTRUMENTLIST
}
