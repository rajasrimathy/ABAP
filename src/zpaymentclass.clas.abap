CLASS zpaymentclass DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
  METHODS: ZPayment IMPORTING iv_xml_document TYPE string.
   PROTECTED SECTION.
ENDCLASS.



CLASS zpaymentclass IMPLEMENTATION.
 METHOD ZPayment.

 DATA(xml_strg) = iv_xml_document.

    DATA lv_message_id TYPE string.
    DATA lv_client_id TYPE string.
    DATA lv_msgsrc_id TYPE string.
    DATA(xml_strg2) = iv_xml_document.
    "Creating XML
    DATA(lv_response_xml) = cl_abap_conv_codepage=>create_out( )->convert( xml_strg ).

    "iXML
    DATA(lo_ixml_pa) = cl_ixml_core=>create( ).
    DATA(lo_stream_factory_pa) = lo_ixml_pa->create_stream_factory( ).
    DATA(lo_document_pa) = lo_ixml_pa->create_document( ).

    "XML Parser
    DATA(lo_parser_pa) = lo_ixml_pa->create_parser(
                    istream = lo_stream_factory_pa->create_istream_xstring( string = lv_response_xml )
                    document = lo_document_pa
                    stream_factory = lo_stream_factory_pa ).
    "Check XML Parser
    DATA(parsing_check) = lo_parser_pa->parse( ).
    "IF XML Parser contains no error
    IF parsing_check = 0.
      "Iterator
      DATA(lo_iterator_pa) = lo_document_pa->create_iterator( ).
      DO.
        DATA(lo_node_i) = lo_iterator_pa->get_next( ).
        IF lo_node_i IS INITIAL.
          EXIT.
        ELSE.
          IF lo_node_i->get_name( ) = 'MessageId'.
            lv_message_id = lo_node_i->get_value( ).

          ENDIF.
          IF lo_node_i->get_name( ) = 'MsgSource'.
            lv_msgsrc_id = lo_node_i->get_value( ).

          ENDIF.
          IF lo_node_i->get_name( ) = 'ClientCode'.
            lv_client_id = lo_node_i->get_value( ).
            EXIT.
          ENDIF.
        ENDIF.
      ENDDO.
    ENDIF.


        DATA(xml_string) = iv_xml_document.

    CALL TRANSFORMATION id
            SOURCE XML xml_string
            RESULT XML DATA(xml_data).
    DATA: lo_http_destination       TYPE REF TO if_http_destination,
          lo_web_http_client        TYPE REF TO if_web_http_client,
          lo_web_http_get_request   TYPE REF TO if_web_http_request,
          lo_web_http_get_response  TYPE REF TO if_web_http_response,
          lo_web_http_post_request  TYPE REF TO if_web_http_request,
          lo_web_http_post_response TYPE REF TO if_web_http_response,
          lv_response               TYPE string,
          lv_response_code          TYPE string,
          lv_csrf_token             TYPE string.

        DATA jso TYPE string.
    jso = '{"ZPaymentFileReference": "' && lv_message_id && '","ZClientcode": "' && lv_client_id && '","ZMessagesourcecode": "' && lv_msgsrc_id && '","ZFileContent": "' && xml_data && '" ,"HasActiveEntity": false,"IsActiveEntity": true}'.
    TRY.
        lo_http_destination = cl_http_destination_provider=>create_by_comm_arrangement( comm_scenario = 'ZOUTGOINGPAYMENT' ).

        lo_web_http_client = cl_web_http_client_manager=>create_by_http_destination( lo_http_destination ).

        lo_web_http_get_request = lo_web_http_client->get_http_request( ).

        lo_web_http_get_request->set_header_fields( VALUE #( ( name = 'x-csrf-token' value = 'fetch' ) ) ).

        lo_web_http_get_response = lo_web_http_client->execute( if_web_http_client=>get ).
        lv_response = lo_web_http_get_response->get_text( ).
        lv_response_code = lo_web_http_get_response->get_status( )-code.

        lv_csrf_token = lo_web_http_get_response->get_header_field( i_name = 'x-csrf-token' ).

        IF lv_csrf_token IS NOT INITIAL.

          lo_web_http_post_request = lo_web_http_client->get_http_request( ).

          lo_web_http_post_request->set_header_fields( VALUE #( ( name = 'x-csrf-token' value = lv_csrf_token ) ) ).
          lo_web_http_post_request->set_content_type( content_type = 'application/json' ).
          IF jso IS NOT INITIAL.
            lo_web_http_post_request->set_text( jso ).
            lo_web_http_post_response = lo_web_http_client->execute( if_web_http_client=>post ).
            lv_response = lo_web_http_post_response->get_text( ).
            lv_response_code = lo_web_http_post_response->get_status( )-code.


          ENDIF.
        ENDIF.

      CATCH cx_http_dest_provider_error.
      CATCH cx_web_http_client_error.
      CATCH cx_web_message_error.

    ENDTRY.


  ENDMETHOD.
ENDCLASS.
