CLASS zsendpaymentdetails DEFINITION
 PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_apj_dt_exec_object .
    INTERFACES if_apj_rt_exec_object .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zsendpaymentdetails IMPLEMENTATION.


  METHOD if_apj_dt_exec_object~get_parameters.
  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.

    DATA lv_short_time_stamp TYPE timestampl.
    GET TIME STAMP FIELD lv_short_time_stamp.

    "Select all the payment details if payment sync is false.
    DATA: totalpaymentdetails TYPE TABLE OF zpaymentdetails.

    SELECT ( '*' ) FROM zpaymentdetails WHERE z_paymentsync = '' INTO TABLE @totalpaymentdetails.

    "Get one by one in loop
    LOOP AT totalpaymentdetails INTO DATA(totals).

      DATA: system_uuid_log TYPE REF TO if_system_uuid,
            uuid_log        TYPE sysuuid_c32.

      DATA: ls_paymentlog TYPE zpaymentlog.

      " Select particular details
      SELECT * FROM zpaymentdetails WHERE z_payment_uuid = @totals-z_payment_uuid INTO TABLE @DATA(paymentdetail).

      LOOP AT paymentdetail INTO DATA(getdetails).

        IF paymentdetail IS NOT INITIAL.

          "Payment Sync Check
          DATA paymentsync.

          "Get Current File content Details
          DATA filecontent TYPE string.

          filecontent = getdetails-z_encryptedfile.
          paymentsync = getdetails-z_paymentsync.

          IF paymentsync IS INITIAL AND filecontent IS NOT INITIAL.

            "Create client id and client secret field for pass value runtime via API.
            DATA clientid TYPE string.
            DATA clientsecret TYPE string.

            DATA: lt_data TYPE TABLE OF zconfiguration,
                  ls_data TYPE zconfiguration.

            "Select data from a configuration table
            SELECT * FROM zconfiguration WHERE z_id = 'ROOT' INTO TABLE @lt_data.

            IF lt_data IS NOT INITIAL.
              LOOP AT lt_data INTO ls_data.
                clientid = ls_data-z_client_id.
                clientsecret = ls_data-z_client_secret.
              ENDLOOP.
            ENDIF.

            TRY.
                "API call for Post Payment Details.
                DATA(loo_destination_payment) = cl_http_destination_provider=>create_by_comm_arrangement(
                                       comm_scenario  = 'ZPAYMENTAPI_SC'
                                     ).
                DATA(loo_http_client_payment) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_payment ).

                DATA(loo_request_payment) = loo_http_client_payment->get_http_request( ).

                loo_request_payment->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/xml' ) ) ).

                DATA bodycontent TYPE string.

                bodycontent = filecontent.

                loo_request_payment->set_text( bodycontent ).


                "API call for Get Refresh Token.
                DATA(lo_destination_getrefershtoken) = cl_http_destination_provider=>create_by_comm_arrangement(
                                       comm_scenario  = 'ZGETREFRESHTOKEN_SC'
                                     ).
                DATA(lo_http_client_getrefreshtoken) = cl_web_http_client_manager=>create_by_http_destination( lo_destination_getrefershtoken ).

                DATA(lo_request_getrefreshtoken) = lo_http_client_getrefreshtoken->get_http_request( ).

                lo_request_getrefreshtoken->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/x-www-form-urlencoded' ) ) ).

                lo_request_getrefreshtoken->set_form_fields( VALUE #(
                ( name = 'client_id' value = clientid )
                ( name = 'client_secret' value = clientsecret )
                ( name = 'grant_type' value = 'client_credentials' ) ) ).

                "Execute Call.
                DATA(lo_response_getrefreshtoken) = lo_http_client_getrefreshtoken->execute( if_web_http_client=>post ).

                "Result
                DATA(lv_json_getrefreshtoken) = lo_response_getrefreshtoken->get_text( ).

                "Get Status.
                DATA(statuscode_getrefreshtoken) = lo_response_getrefreshtoken->get_status( )-code.

                IF ( statuscode_getrefreshtoken = 200 ).
                  "Extract Response Details.
                  DATA:
                    BEGIN OF ts_tags,
                      access_token TYPE string,
                      token_type   TYPE string,
                      expires_in   TYPE string,
                      scope        TYPE string,
                    END OF ts_tags.
                  /ui2/cl_json=>deserialize( EXPORTING json = lv_json_getrefreshtoken CHANGING data = ts_tags ) .

                  "DATA(accToken) = 'Bearer' && '   ' && ts_tags-access_token.

                  CONCATENATE 'Bearer' ts_tags-access_token INTO DATA(acctoken) SEPARATED BY space.

                  loo_request_payment->set_header_fields( VALUE #(
                  ( name = 'Authorization' value = acctoken ) ) ).

                  "Execute Call.
                  DATA(loo_response_payment) = loo_http_client_payment->execute( if_web_http_client=>post ).

                  "Result
                  DATA(lv_json_payment) = loo_response_payment->get_text( ).

                  "Get Status.
                  DATA(statuscode_payment) = loo_response_payment->get_status( )-code.

                  "API call for Post for Decrypt Details.
                  DATA(loo_destination_decrypt) = cl_http_destination_provider=>create_by_comm_arrangement(
                                   comm_scenario  = 'ZDECRYPTION_SC'
                                       ).
                  DATA(loo_http_client_decrypt) = cl_web_http_client_manager=>create_by_http_destination( loo_destination_decrypt ).

                  DATA(loo_request_decrypt) = loo_http_client_decrypt->get_http_request( ).

                  loo_request_decrypt->set_header_fields( VALUE #( ( name = 'Content-Type' value = 'application/json' ) ) ).

                  DATA decryptcontent TYPE string.

                  decryptcontent = '{ "EncryptedString" : "' && lv_json_payment && '" }'.

                  loo_request_decrypt->set_text( decryptcontent ).

                  DATA(lo_response_decrypt) = loo_http_client_decrypt->execute( if_web_http_client=>post ).

                  "Result
                  DATA(lv_json_decrypt) = lo_response_decrypt->get_text( ).

                  "Get Status.
                  DATA(statuscode_decrypt) = lo_response_decrypt->get_status( )-code.


                  IF ( statuscode_payment = 200 ).

                    REPLACE ALL OCCURRENCES OF '\' IN lv_json_decrypt WITH ''.

                    DATA removelastlen TYPE i.
                    removelastlen = strlen( lv_json_decrypt ).
                    removelastlen = removelastlen - 1.
                    lv_json_decrypt = lv_json_decrypt+0(removelastlen).

                    DATA removefirstlen TYPE i.
                    removefirstlen = strlen( lv_json_decrypt ).
                    removefirstlen = removefirstlen - 1.
                    lv_json_decrypt = lv_json_decrypt+1(removefirstlen).

                    DATA(decryptedxml) = cl_abap_conv_codepage=>create_out( )->convert( source = lv_json_decrypt ).
                    DATA(ixml_pa) = cl_ixml_core=>create( ).
                    DATA(stream_factory_pa) = ixml_pa->create_stream_factory( ).
                    DATA(document_pa) = ixml_pa->create_document( ).

                    DATA(parser_pa) = ixml_pa->create_parser(
                                       istream = stream_factory_pa->create_istream_xstring( string = decryptedxml )
                                       document = document_pa
                                       stream_factory = stream_factory_pa ).
                    DATA(parsing_check) = parser_pa->parse( ).
                    IF parsing_check = 0.
                      DATA(envelope) = document_pa->get_root_element( ).
                      DATA(header) = envelope->get_last_child( ).
                      DATA(body) = header->get_last_child( ).
                      DATA(headerlist) = body->get_first_child( ).
                      DATA messageid TYPE string.
                      DATA statuscd TYPE string.
                      DATA statusrem TYPE string.
                      IF headerlist->get_name(  ) = 'AckHeader'.
                        DATA(headers) = headerlist->get_children( ).
                        DATA(headerslength) = headers->get_length(  ).
                        DATA(k) = 0.
                        WHILE headerslength > k.
                          DATA(headerschild) = headers->get_item( k ).
                          IF headerschild->get_name( ) = 'MessageId'.
                            messageid = headerschild->get_value( ).
                          ELSEIF
                            headerschild->get_name( ) = 'StatusCd'.
                            statuscd = headerschild->get_value( ).
                          ELSEIF
                            headerschild->get_name( ) = 'StatusRem'.
                            statusrem = headerschild->get_value( ).
                          ENDIF.
                          k = k + 1.
                        ENDWHILE.
                        IF statuscd = '008' OR statuscd = '011'.
                          UPDATE zpaymentdetails SET z_paymentmessageid = @messageid, z_paymentstatus = @statusrem, z_paymentstatuscode = @statuscd WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                        ELSE.
                          UPDATE zpaymentdetails SET z_paymentsync = 'X', z_paymentmessageid = @messageid, z_paymentstatus = @statusrem, z_paymentstatuscode = @statuscd WHERE z_payment_uuid = @getdetails-z_payment_uuid.
                        ENDIF.
                      ENDIF.
                      DATA(payment) = body->get_last_child( ).
                      DATA(instrumentlist) = payment->get_children( ).
                      DATA(instrumentcount) = instrumentlist->get_length( ).
                      DATA(i) = 0.
                      WHILE instrumentcount > i.
                        DATA instrefno TYPE string.
                        DATA inststatuscd TYPE string.
                        DATA inststatusrem TYPE string.
                        DATA(j) = 0.
                        DATA(childs) = instrumentlist->get_item( i ).
                        IF childs->get_name(  ) = 'Instrument'.
                          DATA(child) = childs->get_children(  ).
                          DATA(childcount) = child->get_length( ).
                          WHILE childcount > j.
                            DATA(childitemdata) = child->get_item( j ).
                            IF childitemdata->get_name( ) = 'InstRefNo'.
                              instrefno = childitemdata->get_value( ).
                            ELSEIF
                              childitemdata->get_name( ) = 'InstStatusCd'.
                              inststatuscd = childitemdata->get_value( ).
                            ELSEIF
                              childitemdata->get_name( ) = 'InstStatusRem'.
                              inststatusrem = childitemdata->get_value( ).
                            ENDIF.
                            j = j + 1.
                          ENDWHILE.

                          SELECT * FROM zinstrumentlist WHERE z_messageid = @instrefno and z_payment_uuid = @getdetails-z_payment_uuid INTO @DATA(instrument).
                            IF instrument IS NOT INITIAL.
                              UPDATE zinstrumentlist SET z_statuscode = @inststatuscd ,z_statusremark = @inststatusrem WHERE z_messageid = @instrefno.
                            ENDIF.
                          ENDSELECT.

                        ENDIF.
                        i = i + 1.
                      ENDWHILE.
                    ENDIF.

                    system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
                    TRY.
                        uuid_log = system_uuid_log->create_uuid_c32( ).
                      CATCH cx_uuid_error.
                    ENDTRY.

                    ls_paymentlog-z_paymentlog_uuid  = uuid_log.
                    ls_paymentlog-z_payment_uuid = getdetails-z_payment_uuid.
                    ls_paymentlog-z_responsecode = statuscode_payment.
                    ls_paymentlog-z_response = lv_json_decrypt.
                    ls_paymentlog-z_createdby = cl_abap_context_info=>get_user_technical_name( ).
                    ls_paymentlog-z_createdate = lv_short_time_stamp.
                    ls_paymentlog-z_lastchangedby = cl_abap_context_info=>get_user_technical_name( ).
                    ls_paymentlog-z_lastchangedate = lv_short_time_stamp.
                    ls_paymentlog-z_locallastchangedate = lv_short_time_stamp.

                    INSERT INTO zpaymentlog VALUES @ls_paymentlog.

                  ELSE.

                    system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
                    TRY.
                        uuid_log = system_uuid_log->create_uuid_c32( ).
                      CATCH cx_uuid_error.
                    ENDTRY.

                    ls_paymentlog-z_paymentlog_uuid  = uuid_log.
                    ls_paymentlog-z_payment_uuid = getdetails-z_payment_uuid.
                    ls_paymentlog-z_responsecode = statuscode_payment.
                    ls_paymentlog-z_response = lv_json_payment.
                    ls_paymentlog-z_createdby = cl_abap_context_info=>get_user_technical_name( ).
                    ls_paymentlog-z_createdate = lv_short_time_stamp.
                    ls_paymentlog-z_lastchangedby = cl_abap_context_info=>get_user_technical_name( ).
                    ls_paymentlog-z_lastchangedate = lv_short_time_stamp.
                    ls_paymentlog-z_locallastchangedate = lv_short_time_stamp.

                    INSERT INTO zpaymentlog VALUES @ls_paymentlog.
                  ENDIF.

                ELSE.

                  system_uuid_log = cl_uuid_factory=>create_system_uuid( ).
                  TRY.
                      uuid_log = system_uuid_log->create_uuid_c32( ).
                    CATCH cx_uuid_error.
                  ENDTRY.


                  ls_paymentlog-z_paymentlog_uuid  = uuid_log.
                  ls_paymentlog-z_payment_uuid = getdetails-z_payment_uuid.
                  ls_paymentlog-z_responsecode = statuscode_getrefreshtoken.
                  ls_paymentlog-z_response = lv_json_getrefreshtoken.
                  ls_paymentlog-z_createdby = cl_abap_context_info=>get_user_technical_name( ).
                  ls_paymentlog-z_createdate = lv_short_time_stamp.
                  ls_paymentlog-z_lastchangedby = cl_abap_context_info=>get_user_technical_name( ).
                  ls_paymentlog-z_lastchangedate = lv_short_time_stamp.
                  ls_paymentlog-z_locallastchangedate = lv_short_time_stamp.


                  INSERT INTO zpaymentlog VALUES @ls_paymentlog.
                ENDIF.

              CATCH cx_http_dest_provider_error.
                " handle exception here.

              CATCH cx_web_http_client_error.
                " handle exception here

            ENDTRY.

          ENDIF.

        ENDIF.

      ENDLOOP.

    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
